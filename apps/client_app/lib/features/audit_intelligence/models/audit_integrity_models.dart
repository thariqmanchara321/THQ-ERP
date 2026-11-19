import '../audit_widgets.dart';

/// Represents a business or financial integrity check returned by [audit_checks_v704].
class AuditIntegrityCheck {
  const AuditIntegrityCheck({
    required this.id,
    required this.category,
    required this.reference,
    required this.title,
    required this.status,
    required this.severity,
    this.count = 0,
    this.amount,
    this.difference,
    this.expected,
    this.actual,
    this.dataset,
    this.isActionable = true,
    required this.basis,
    required this.explanation,
    this.verifiedChains,
    this.partialScopeChains,
  });

  final String id;
  final String category;
  final String reference;
  final String title;
  final String status;
  final String severity;
  final int count;
  final num? amount;
  final num? difference;
  final num? expected;
  final num? actual;
  final String? dataset;
  final bool isActionable;
  final String basis;
  final String explanation;
  final int? verifiedChains;
  final int? partialScopeChains;

  factory AuditIntegrityCheck.fromJson(Map<String, dynamic> json) {
    return AuditIntegrityCheck(
      id: auditText(json['id']),
      category: auditText(json['category'], fallback: 'accounting'),
      reference: auditText(json['reference']),
      title: auditText(json['title']),
      status: auditText(json['status'], fallback: 'Needs review'),
      severity: auditText(json['severity'], fallback: 'medium').toLowerCase(),
      count: auditNumber(json['count']).toInt(),
      amount: json['amount'] != null ? auditNumber(json['amount']) : null,
      difference:
          json['difference'] != null ? auditNumber(json['difference']) : null,
      expected: json['expected'] != null ? auditNumber(json['expected']) : null,
      actual: json['actual'] != null ? auditNumber(json['actual']) : null,
      dataset: json['dataset']?.toString(),
      isActionable: json['is_actionable'] != false,
      basis: auditText(json['basis']),
      explanation: auditText(json['explanation']),
      verifiedChains: json['verified_chains'] != null
          ? auditNumber(json['verified_chains']).toInt()
          : null,
      partialScopeChains: json['partial_scope_chains'] != null
          ? auditNumber(json['partial_scope_chains']).toInt()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'reference': reference,
    'title': title,
    'status': status,
    'severity': severity,
    'count': count,
    'amount': amount,
    'difference': difference,
    'expected': expected,
    'actual': actual,
    'dataset': dataset,
    'is_actionable': isActionable,
    'basis': basis,
    'explanation': explanation,
    if (verifiedChains != null) 'verified_chains': verifiedChains,
    if (partialScopeChains != null) 'partial_scope_chains': partialScopeChains,
  };

  bool get isPassed => status.toLowerCase() == 'passed';
  bool get isIssueDetected =>
      status.toLowerCase() == 'issue detected' ||
      status.toLowerCase() == 'high risk';
  bool get isNeedsReview => status.toLowerCase() == 'needs review';
  bool get isInsufficientData =>
      status.toLowerCase() == 'insufficient data' ||
      status.toLowerCase() == 'not supplied';
  bool get isNotApplicable => status.toLowerCase() == 'not applicable';
  bool get isUnableToEvaluate => status.toLowerCase() == 'unable to evaluate';

  bool get isCritical => severity == 'critical';
  bool get isHigh => severity == 'high';
  bool get isMedium => severity == 'medium';
  bool get isLow => severity == 'low';
}

/// Represents the top-level envelope returned by [audit_checks_v704].
class AuditIntegrityResult {
  const AuditIntegrityResult({
    required this.checks,
    required this.totalRows,
    this.generatedAt,
    required this.basis,
  });

  final List<AuditIntegrityCheck> checks;
  final int totalRows;
  final DateTime? generatedAt;
  final String basis;

  factory AuditIntegrityResult.fromJson(Map<String, dynamic> json) {
    final rowsRaw = json['rows'];
    final list = rowsRaw is List ? rowsRaw : const [];
    return AuditIntegrityResult(
      checks: list
          .whereType<Map<String, dynamic>>()
          .map(AuditIntegrityCheck.fromJson)
          .toList(growable: false),
      totalRows: auditNumber(json['total_rows']).toInt(),
      generatedAt: json['generated_at'] != null
          ? DateTime.tryParse(json['generated_at'].toString())
          : null,
      basis: auditText(json['basis']),
    );
  }

  int get totalCount => checks.length;
  int get passedCount => checks.where((c) => c.isPassed).length;
  int get issueCount => checks.where((c) => c.isIssueDetected).length;
  int get reviewCount => checks.where((c) => c.isNeedsReview).length;
  int get insufficientDataCount =>
      checks.where((c) => c.isInsufficientData).length;

  List<AuditIntegrityCheck> get issuesAndReviews =>
      checks.where((c) => c.isIssueDetected || c.isNeedsReview).toList();

  List<AuditIntegrityCheck> byCategory(String category) {
    if (category.isEmpty || category.toLowerCase() == 'all') return checks;
    return checks
        .where(
          (c) =>
              c.category.toLowerCase() == category.toLowerCase() ||
              (category == 'sales_purchase' &&
                  (c.category == 'sales' || c.category == 'purchases')),
        )
        .toList();
  }
}

/// Represents an individual affected record returned by [audit_check_records_v704]
/// for drill-down into source evidence.
class AuditCheckDrilldownRecord {
  const AuditCheckDrilldownRecord({
    required this.id,
    required this.reference,
    this.date,
    required this.dataset,
    this.expectedValue,
    this.actualValue,
    this.difference,
    required this.description,
  });

  final String id;
  final String reference;
  final String? date;
  final String dataset;
  final dynamic expectedValue;
  final dynamic actualValue;
  final dynamic difference;
  final String description;

  factory AuditCheckDrilldownRecord.fromJson(Map<String, dynamic> json) {
    return AuditCheckDrilldownRecord(
      id: auditText(json['id']),
      reference: auditText(json['reference']),
      date: json['date']?.toString(),
      dataset: auditText(json['dataset']),
      expectedValue: json['expected_value'],
      actualValue: json['actual_value'],
      difference: json['difference'],
      description: auditText(json['description']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'reference': reference,
    'date': date,
    'dataset': dataset,
    'expected_value': expectedValue,
    'actual_value': actualValue,
    'difference': difference,
    'description': description,
  };
}

/// Represents the drilldown envelope returned by [audit_check_records_v704].
class AuditCheckDrilldownResult {
  const AuditCheckDrilldownResult({
    required this.checkId,
    required this.dataset,
    required this.title,
    required this.rule,
    required this.totalRecords,
    required this.records,
  });

  final String checkId;
  final String dataset;
  final String title;
  final String rule;
  final int totalRecords;
  final List<AuditCheckDrilldownRecord> records;

  factory AuditCheckDrilldownResult.fromJson(Map<String, dynamic> json) {
    final list = json['records'];
    return AuditCheckDrilldownResult(
      checkId: auditText(json['check_id']),
      dataset: auditText(json['dataset']),
      title: auditText(json['title']),
      rule: auditText(json['rule']),
      totalRecords: auditNumber(json['total_records']).toInt(),
      records: (list is List ? list : const [])
          .whereType<Map<String, dynamic>>()
          .map(AuditCheckDrilldownRecord.fromJson)
          .toList(growable: false),
    );
  }
}
