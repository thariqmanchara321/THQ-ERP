/// High-level engine classifications for Operations Intelligence.
enum IntelligenceEngineType {
  executiveHealth,
  sales,
  inventory,
  financial,
  customer,
  supplier,
  procurement,
  operationalEfficiency,
  workforce,
  riskAnomaly,
  predictive,
  simulation;

  String get code {
    switch (this) {
      case IntelligenceEngineType.executiveHealth:
        return 'executive';
      case IntelligenceEngineType.sales:
        return 'sales';
      case IntelligenceEngineType.inventory:
        return 'inventory';
      case IntelligenceEngineType.financial:
        return 'financial';
      case IntelligenceEngineType.customer:
        return 'customer';
      case IntelligenceEngineType.supplier:
        return 'supplier';
      case IntelligenceEngineType.procurement:
        return 'procurement';
      case IntelligenceEngineType.operationalEfficiency:
        return 'operations';
      case IntelligenceEngineType.workforce:
        return 'workforce';
      case IntelligenceEngineType.riskAnomaly:
        return 'risk_anomaly';
      case IntelligenceEngineType.predictive:
        return 'predictive';
      case IntelligenceEngineType.simulation:
        return 'simulation';
    }
  }

  static IntelligenceEngineType fromCode(String? code) {
    switch (code) {
      case 'executive':
        return IntelligenceEngineType.executiveHealth;
      case 'sales':
        return IntelligenceEngineType.sales;
      case 'inventory':
        return IntelligenceEngineType.inventory;
      case 'financial':
        return IntelligenceEngineType.financial;
      case 'customer':
        return IntelligenceEngineType.customer;
      case 'supplier':
        return IntelligenceEngineType.supplier;
      case 'procurement':
        return IntelligenceEngineType.procurement;
      case 'operations':
        return IntelligenceEngineType.operationalEfficiency;
      case 'workforce':
        return IntelligenceEngineType.workforce;
      case 'risk_anomaly':
        return IntelligenceEngineType.riskAnomaly;
      case 'predictive':
        return IntelligenceEngineType.predictive;
      case 'simulation':
        return IntelligenceEngineType.simulation;
      default:
        return IntelligenceEngineType.executiveHealth;
    }
  }
}

/// Severity classification of an insight.
enum InsightSeverity {
  info,
  warning,
  critical,
  opportunity;

  String get code => name;

  static InsightSeverity fromCode(String? code) {
    switch (code) {
      case 'critical':
        return InsightSeverity.critical;
      case 'warning':
        return InsightSeverity.warning;
      case 'opportunity':
        return InsightSeverity.opportunity;
      case 'info':
      default:
        return InsightSeverity.info;
    }
  }
}

/// Operational urgency / prioritization of an insight.
enum InsightPriority {
  low,
  medium,
  high,
  urgent;

  String get code => name;

  static InsightPriority fromCode(String? code) {
    switch (code) {
      case 'urgent':
        return InsightPriority.urgent;
      case 'high':
        return InsightPriority.high;
      case 'medium':
        return InsightPriority.medium;
      case 'low':
      default:
        return InsightPriority.low;
    }
  }
}

/// Lifecycle state of an insight.
enum InsightStatus {
  newInsight,
  acknowledged,
  inProgress,
  resolved,
  dismissed,
  reopened;

  String get code {
    switch (this) {
      case InsightStatus.newInsight:
        return 'new_insight';
      case InsightStatus.acknowledged:
        return 'acknowledged';
      case InsightStatus.inProgress:
        return 'in_progress';
      case InsightStatus.resolved:
        return 'resolved';
      case InsightStatus.dismissed:
        return 'dismissed';
      case InsightStatus.reopened:
        return 'reopened';
    }
  }

  static InsightStatus fromCode(String? code) {
    switch (code) {
      case 'acknowledged':
        return InsightStatus.acknowledged;
      case 'in_progress':
        return InsightStatus.inProgress;
      case 'resolved':
        return InsightStatus.resolved;
      case 'dismissed':
        return InsightStatus.dismissed;
      case 'reopened':
        return InsightStatus.reopened;
      case 'new_insight':
      default:
        return InsightStatus.newInsight;
    }
  }
}

/// Action proposal types.
enum ActionType {
  createPurchaseOrder,
  createStockTransfer,
  sendPaymentReminder,
  adjustReorderLevel,
  freezeCustomerCredit,
  operationalTask;

  String get code {
    switch (this) {
      case ActionType.createPurchaseOrder:
        return 'create_purchase_order';
      case ActionType.createStockTransfer:
        return 'create_stock_transfer';
      case ActionType.sendPaymentReminder:
        return 'send_payment_reminder';
      case ActionType.adjustReorderLevel:
        return 'adjust_reorder_level';
      case ActionType.freezeCustomerCredit:
        return 'freeze_customer_credit';
      case ActionType.operationalTask:
        return 'operational_task';
    }
  }

  static ActionType fromCode(String? code) {
    switch (code) {
      case 'create_purchase_order':
        return ActionType.createPurchaseOrder;
      case 'create_stock_transfer':
        return ActionType.createStockTransfer;
      case 'send_payment_reminder':
        return ActionType.sendPaymentReminder;
      case 'adjust_reorder_level':
        return ActionType.adjustReorderLevel;
      case 'freeze_customer_credit':
        return ActionType.freezeCustomerCredit;
      case 'operational_task':
      default:
        return ActionType.operationalTask;
    }
  }
}

/// Status of an action proposal.
enum ActionStatus {
  pendingApproval,
  approved,
  rejected,
  executed,
  failed;

  String get code {
    switch (this) {
      case ActionStatus.pendingApproval:
        return 'pending_approval';
      case ActionStatus.approved:
        return 'approved';
      case ActionStatus.rejected:
        return 'rejected';
      case ActionStatus.executed:
        return 'executed';
      case ActionStatus.failed:
        return 'failed';
    }
  }

  static ActionStatus fromCode(String? code) {
    switch (code) {
      case 'approved':
        return ActionStatus.approved;
      case 'rejected':
        return ActionStatus.rejected;
      case 'executed':
        return ActionStatus.executed;
      case 'failed':
        return ActionStatus.failed;
      case 'pending_approval':
      default:
        return ActionStatus.pendingApproval;
    }
  }
}

/// Source reference linking an insight to canonical ERP records.
class InsightSourceReference {
  final String entityType;
  final String entityId;
  final String? entityNumber;
  final String? route;

  const InsightSourceReference({
    required this.entityType,
    required this.entityId,
    this.entityNumber,
    this.route,
  });

  factory InsightSourceReference.fromMap(Map<String, dynamic> map) =>
      InsightSourceReference(
        entityType: map['entity_type']?.toString() ?? '',
        entityId: map['entity_id']?.toString() ?? '',
        entityNumber: map['entity_number']?.toString(),
        route: map['route']?.toString(),
      );

  Map<String, dynamic> toMap() => {
    'entity_type': entityType,
    'entity_id': entityId,
    if (entityNumber != null) 'entity_number': entityNumber,
    if (route != null) 'route': route,
  };
}

/// Verifiable evidence supporting an insight calculation.
class InsightEvidence {
  final double? currentValue;
  final double? previousValue;
  final double? targetValue;
  final double? varianceValue;
  final double? variancePercentage;
  final double? threshold;
  final int? sampleCount;
  final String? metricUnit;
  final Map<String, dynamic> breakdown;

  const InsightEvidence({
    this.currentValue,
    this.previousValue,
    this.targetValue,
    this.varianceValue,
    this.variancePercentage,
    this.threshold,
    this.sampleCount,
    this.metricUnit,
    this.breakdown = const {},
  });

  factory InsightEvidence.fromMap(Map<String, dynamic> map) {
    double? d(dynamic v) => (v as num?)?.toDouble();
    return InsightEvidence(
      currentValue: d(map['current_value']),
      previousValue: d(map['previous_value']),
      targetValue: d(map['target_value']),
      varianceValue: d(map['variance_value']),
      variancePercentage: d(map['variance_percentage']),
      threshold: d(map['threshold']),
      sampleCount: (map['sample_count'] as num?)?.toInt(),
      metricUnit: map['metric_unit']?.toString(),
      breakdown: map['breakdown'] is Map
          ? Map<String, dynamic>.from(map['breakdown'] as Map)
          : const {},
    );
  }

  Map<String, dynamic> toMap() => {
    if (currentValue != null) 'current_value': currentValue,
    if (previousValue != null) 'previous_value': previousValue,
    if (targetValue != null) 'target_value': targetValue,
    if (varianceValue != null) 'variance_value': varianceValue,
    if (variancePercentage != null) 'variance_percentage': variancePercentage,
    if (threshold != null) 'threshold': threshold,
    if (sampleCount != null) 'sample_count': sampleCount,
    if (metricUnit != null) 'metric_unit': metricUnit,
    if (breakdown.isNotEmpty) 'breakdown': breakdown,
  };
}

/// Standardized canonical insight record across all intelligence engines.
class InsightRecord {
  final String id;
  final String tenantId;
  final String? locationId;
  final IntelligenceEngineType engine;
  final String category;
  final InsightSeverity severity;
  final InsightPriority priority;
  final String title;
  final String description;
  final InsightEvidence evidence;
  final List<InsightSourceReference> sourceReferences;
  final double confidence;
  final DateTime dataFreshness;
  final InsightStatus status;
  final String? resolutionNote;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const InsightRecord({
    required this.id,
    required this.tenantId,
    this.locationId,
    required this.engine,
    required this.category,
    required this.severity,
    required this.priority,
    required this.title,
    required this.description,
    this.evidence = const InsightEvidence(),
    this.sourceReferences = const [],
    this.confidence = 1.0,
    required this.dataFreshness,
    this.status = InsightStatus.newInsight,
    this.resolutionNote,
    this.resolvedBy,
    this.resolvedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InsightRecord.fromMap(Map<String, dynamic> map) {
    return InsightRecord(
      id: map['id']?.toString() ?? '',
      tenantId: map['tenant_id']?.toString() ?? '',
      locationId: map['location_id']?.toString(),
      engine: IntelligenceEngineType.fromCode(map['engine']?.toString()),
      category: map['category']?.toString() ?? 'general',
      severity: InsightSeverity.fromCode(map['severity']?.toString()),
      priority: InsightPriority.fromCode(map['priority']?.toString()),
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      evidence: map['evidence'] is Map
          ? InsightEvidence.fromMap(Map<String, dynamic>.from(map['evidence'] as Map))
          : const InsightEvidence(),
      sourceReferences: (map['source_references'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => InsightSourceReference.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
      dataFreshness: DateTime.tryParse(map['data_freshness']?.toString() ?? '') ?? DateTime.now(),
      status: InsightStatus.fromCode(map['status']?.toString()),
      resolutionNote: map['resolution_note']?.toString(),
      resolvedBy: map['resolved_by']?.toString(),
      resolvedAt: map['resolved_at'] != null ? DateTime.tryParse(map['resolved_at'].toString()) : null,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'tenant_id': tenantId,
    if (locationId != null) 'location_id': locationId,
    'engine': engine.code,
    'category': category,
    'severity': severity.code,
    'priority': priority.code,
    'title': title,
    'description': description,
    'evidence': evidence.toMap(),
    'source_references': sourceReferences.map((e) => e.toMap()).toList(),
    'confidence': confidence,
    'data_freshness': dataFreshness.toIso8601String(),
    'status': status.code,
    if (resolutionNote != null) 'resolution_note': resolutionNote,
    if (resolvedBy != null) 'resolved_by': resolvedBy,
    if (resolvedAt != null) 'resolved_at': resolvedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  InsightRecord copyWith({
    String? id,
    String? tenantId,
    String? locationId,
    IntelligenceEngineType? engine,
    String? category,
    InsightSeverity? severity,
    InsightPriority? priority,
    String? title,
    String? description,
    InsightEvidence? evidence,
    List<InsightSourceReference>? sourceReferences,
    double? confidence,
    DateTime? dataFreshness,
    InsightStatus? status,
    String? resolutionNote,
    String? resolvedBy,
    DateTime? resolvedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => InsightRecord(
    id: id ?? this.id,
    tenantId: tenantId ?? this.tenantId,
    locationId: locationId ?? this.locationId,
    engine: engine ?? this.engine,
    category: category ?? this.category,
    severity: severity ?? this.severity,
    priority: priority ?? this.priority,
    title: title ?? this.title,
    description: description ?? this.description,
    evidence: evidence ?? this.evidence,
    sourceReferences: sourceReferences ?? this.sourceReferences,
    confidence: confidence ?? this.confidence,
    dataFreshness: dataFreshness ?? this.dataFreshness,
    status: status ?? this.status,
    resolutionNote: resolutionNote ?? this.resolutionNote,
    resolvedBy: resolvedBy ?? this.resolvedBy,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Action Proposal ready for human approval and execution.
class ActionProposal {
  final String id;
  final String tenantId;
  final String? locationId;
  final String? insightId;
  final ActionType actionType;
  final Map<String, dynamic> payload;
  final String previewSummary;
  final String requiredPermission;
  final ActionStatus status;
  final String? createdBy;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime? executedAt;
  final Map<String, dynamic>? executionResult;
  final DateTime createdAt;

  const ActionProposal({
    required this.id,
    required this.tenantId,
    this.locationId,
    this.insightId,
    required this.actionType,
    required this.payload,
    required this.previewSummary,
    this.requiredPermission = 'inventory.manage',
    this.status = ActionStatus.pendingApproval,
    this.createdBy,
    this.approvedBy,
    this.approvedAt,
    this.executedAt,
    this.executionResult,
    required this.createdAt,
  });

  factory ActionProposal.fromMap(Map<String, dynamic> map) {
    return ActionProposal(
      id: map['id']?.toString() ?? '',
      tenantId: map['tenant_id']?.toString() ?? '',
      locationId: map['location_id']?.toString(),
      insightId: map['insight_id']?.toString(),
      actionType: ActionType.fromCode(map['action_type']?.toString()),
      payload: map['payload'] is Map ? Map<String, dynamic>.from(map['payload'] as Map) : {},
      previewSummary: map['preview_summary']?.toString() ?? '',
      requiredPermission: map['required_permission']?.toString() ?? 'inventory.manage',
      status: ActionStatus.fromCode(map['status']?.toString()),
      createdBy: map['created_by']?.toString(),
      approvedBy: map['approved_by']?.toString(),
      approvedAt: map['approved_at'] != null ? DateTime.tryParse(map['approved_at'].toString()) : null,
      executedAt: map['executed_at'] != null ? DateTime.tryParse(map['executed_at'].toString()) : null,
      executionResult: map['execution_result'] is Map ? Map<String, dynamic>.from(map['execution_result'] as Map) : null,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'tenant_id': tenantId,
    if (locationId != null) 'location_id': locationId,
    if (insightId != null) 'insight_id': insightId,
    'action_type': actionType.code,
    'payload': payload,
    'preview_summary': previewSummary,
    'required_permission': requiredPermission,
    'status': status.code,
    if (createdBy != null) 'created_by': createdBy,
    if (approvedBy != null) 'approved_by': approvedBy,
    if (approvedAt != null) 'approved_at': approvedAt?.toIso8601String(),
    if (executedAt != null) 'executed_at': executedAt?.toIso8601String(),
    if (executionResult != null) 'execution_result': executionResult,
    'created_at': createdAt.toIso8601String(),
  };

  ActionProposal copyWith({
    String? id,
    String? tenantId,
    String? locationId,
    String? insightId,
    ActionType? actionType,
    Map<String, dynamic>? payload,
    String? previewSummary,
    String? requiredPermission,
    ActionStatus? status,
    String? createdBy,
    String? approvedBy,
    DateTime? approvedAt,
    DateTime? executedAt,
    Map<String, dynamic>? executionResult,
    DateTime? createdAt,
  }) => ActionProposal(
    id: id ?? this.id,
    tenantId: tenantId ?? this.tenantId,
    locationId: locationId ?? this.locationId,
    insightId: insightId ?? this.insightId,
    actionType: actionType ?? this.actionType,
    payload: payload ?? this.payload,
    previewSummary: previewSummary ?? this.previewSummary,
    requiredPermission: requiredPermission ?? this.requiredPermission,
    status: status ?? this.status,
    createdBy: createdBy ?? this.createdBy,
    approvedBy: approvedBy ?? this.approvedBy,
    approvedAt: approvedAt ?? this.approvedAt,
    executedAt: executedAt ?? this.executedAt,
    executionResult: executionResult ?? this.executionResult,
    createdAt: createdAt ?? this.createdAt,
  );
}

/// Executive Business Health Snapshot.
class ExecutiveHealthSnapshot {
  final int periodDays;
  final DateTime fromDate;
  final DateTime toDate;
  final double grossSales;
  final double salesReturns;
  final double netSales;
  final double grossProfit;
  final double grossMarginPct;
  final double expenses;
  final double netOperatingProfit;
  final int orderCount;
  final double averageOrderValue;
  final double inventoryValue;
  final int totalMonitoredVariants;
  final int lowStockCount;
  final int outOfStockCount;
  final int deadStockCount;
  final int overstockCount;
  final double receivables;
  final double overdueReceivables;
  final double payables;
  final double overduePayables;
  final int unresolvedInsightsCount;
  final int criticalInsightsCount;
  final int pendingActionsCount;
  final double compositeHealthScore;
  final Map<String, dynamic> pipeline;
  final List<Map<String, dynamic>> topProducts;
  final List<Map<String, dynamic>> hourlyDistribution;

  const ExecutiveHealthSnapshot({
    required this.periodDays,
    required this.fromDate,
    required this.toDate,
    required this.grossSales,
    required this.salesReturns,
    required this.netSales,
    required this.grossProfit,
    required this.grossMarginPct,
    required this.expenses,
    required this.netOperatingProfit,
    required this.orderCount,
    required this.averageOrderValue,
    required this.inventoryValue,
    required this.totalMonitoredVariants,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.deadStockCount,
    required this.overstockCount,
    required this.receivables,
    required this.overdueReceivables,
    required this.payables,
    required this.overduePayables,
    required this.unresolvedInsightsCount,
    required this.criticalInsightsCount,
    required this.pendingActionsCount,
    required this.compositeHealthScore,
    this.pipeline = const {},
    this.topProducts = const [],
    this.hourlyDistribution = const [],
  });

  factory ExecutiveHealthSnapshot.fromMap(Map<String, dynamic> map) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
    int i(dynamic v) => (v as num?)?.toInt() ?? 0;

    final gross = d(map['gross_sales']);
    final ret = d(map['sales_returns']);
    final net = d(map['net_sales']) > 0 ? d(map['net_sales']) : (gross - ret);
    final profit = d(map['gross_profit']);
    final margin = d(map['gross_margin_pct']);
    final exp = d(map['expenses']);
    final netProf = d(map['net_operating_profit']);

    // Calculate deterministic composite business health score (0 to 100)
    // Factors: Margin health (30%), Liquidity ratio (25%), Stock health (25%), Pipeline friction (20%)
    double score = 100.0;
    if (margin < 10.0) score -= 15.0;
    if (margin < 5.0) score -= 15.0;
    if (exp > net * 0.4 && net > 0) score -= 10.0;
    final overdueRecv = d(map['overdue_receivables']);
    final totalRecv = d(map['receivables']);
    if (totalRecv > 0 && (overdueRecv / totalRecv) > 0.3) score -= 15.0;
    final outStock = i(map['out_of_stock_count']);
    final totalVars = i(map['total_monitored_variants']);
    if (totalVars > 0 && (outStock / totalVars) > 0.1) score -= 15.0;
    final critInsights = i(map['critical_insights_count']);
    score -= (critInsights * 5.0);
    score = score.clamp(0.0, 100.0);

    return ExecutiveHealthSnapshot(
      periodDays: i(map['period_days']) > 0 ? i(map['period_days']) : 30,
      fromDate: DateTime.tryParse(map['from_date']?.toString() ?? '') ?? DateTime.now().subtract(const Duration(days: 30)),
      toDate: DateTime.tryParse(map['to_date']?.toString() ?? '') ?? DateTime.now(),
      grossSales: gross,
      salesReturns: ret,
      netSales: net,
      grossProfit: profit,
      grossMarginPct: margin,
      expenses: exp,
      netOperatingProfit: netProf,
      orderCount: i(map['order_count']),
      averageOrderValue: d(map['average_order_value']),
      inventoryValue: d(map['inventory_value']),
      totalMonitoredVariants: totalVars,
      lowStockCount: i(map['low_stock_count']),
      outOfStockCount: outStock,
      deadStockCount: i(map['dead_stock_count']),
      overstockCount: i(map['overstock_count']),
      receivables: totalRecv,
      overdueReceivables: overdueRecv,
      payables: d(map['payables']),
      overduePayables: d(map['overdue_payables']),
      unresolvedInsightsCount: i(map['unresolved_insights_count']),
      criticalInsightsCount: critInsights,
      pendingActionsCount: i(map['pending_actions_count']),
      compositeHealthScore: score,
      pipeline: map['pipeline'] is Map ? Map<String, dynamic>.from(map['pipeline'] as Map) : const {},
      topProducts: (map['top_products'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      hourlyDistribution: (map['hourly_distribution'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'period_days': periodDays,
    'from_date': fromDate.toIso8601String(),
    'to_date': toDate.toIso8601String(),
    'gross_sales': grossSales,
    'sales_returns': salesReturns,
    'net_sales': netSales,
    'gross_profit': grossProfit,
    'gross_margin_pct': grossMarginPct,
    'expenses': expenses,
    'net_operating_profit': netOperatingProfit,
    'order_count': orderCount,
    'average_order_value': averageOrderValue,
    'inventory_value': inventoryValue,
    'total_monitored_variants': totalMonitoredVariants,
    'low_stock_count': lowStockCount,
    'out_of_stock_count': outOfStockCount,
    'dead_stock_count': deadStockCount,
    'overstock_count': overstockCount,
    'receivables': receivables,
    'overdue_receivables': overdueReceivables,
    'payables': payables,
    'overdue_payables': overduePayables,
    'unresolved_insights_count': unresolvedInsightsCount,
    'critical_insights_count': criticalInsightsCount,
    'pending_actions_count': pendingActionsCount,
    'composite_health_score': compositeHealthScore,
    'pipeline': pipeline,
    'top_products': topProducts,
    'hourly_distribution': hourlyDistribution,
  };
}
