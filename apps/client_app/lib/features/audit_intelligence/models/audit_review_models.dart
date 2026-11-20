import '../audit_widgets.dart';

/// Models for Phase C & D: Advanced Risk Intelligence & Professional Audit Review Workflow.

/// Assignable team member in tenant for audit reviews.
class AuditAssignableUser {
  const AuditAssignableUser({
    required this.userId,
    required this.username,
    this.email,
  });

  final String userId;
  final String username;
  final String? email;

  factory AuditAssignableUser.fromJson(Map<String, dynamic> json) {
    return AuditAssignableUser(
      userId: auditText(json['user_id']),
      username: auditText(json['username'], fallback: 'Reviewer'),
      email: json['email']?.toString(),
    );
  }
}

/// An investigation note added by a reviewer with optional evidence links.
class AuditFindingNote {
  const AuditFindingNote({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.noteType,
    required this.note,
    this.evidenceReferences = const [],
    required this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String noteType;
  final String note;
  final List<Map<String, dynamic>> evidenceReferences;
  final DateTime createdAt;

  factory AuditFindingNote.fromJson(Map<String, dynamic> json) {
    return AuditFindingNote(
      id: auditText(json['id']),
      authorId: auditText(json['author_id']),
      authorName: auditText(json['author_name'], fallback: 'Reviewer'),
      noteType: auditText(json['note_type'], fallback: 'investigation'),
      note: auditText(json['note']),
      evidenceReferences: auditRows(json['evidence_references']),
      createdAt:
          DateTime.tryParse(auditText(json['created_at'])) ?? DateTime.now(),
    );
  }
}

/// Immutable activity history entry representing a workflow transition or action.
class AuditFindingHistoryItem {
  const AuditFindingHistoryItem({
    required this.id,
    required this.action,
    required this.actorId,
    required this.actorName,
    this.beforeState,
    this.afterState,
    this.reason,
    required this.createdAt,
  });

  final String id;
  final String action;
  final String actorId;
  final String actorName;
  final Map<String, dynamic>? beforeState;
  final Map<String, dynamic>? afterState;
  final String? reason;
  final DateTime createdAt;

  factory AuditFindingHistoryItem.fromJson(Map<String, dynamic> json) {
    return AuditFindingHistoryItem(
      id: auditText(json['id']),
      action: auditText(json['action']),
      actorId: auditText(json['actor_id']),
      actorName: auditText(json['actor_name'], fallback: 'User'),
      beforeState: auditMap(json['before_state']),
      afterState: auditMap(json['after_state']),
      reason: json['reason']?.toString(),
      createdAt:
          DateTime.tryParse(auditText(json['created_at'])) ?? DateTime.now(),
    );
  }
}

/// Review workload summary per reviewer.
class AuditReviewWorkload {
  const AuditReviewWorkload({
    this.userId,
    required this.username,
    required this.activeCount,
    required this.criticalCount,
    required this.overdueCount,
  });

  final String? userId;
  final String username;
  final int activeCount;
  final int criticalCount;
  final int overdueCount;

  factory AuditReviewWorkload.fromJson(Map<String, dynamic> json) {
    return AuditReviewWorkload(
      userId: json['user_id']?.toString(),
      username: auditText(json['username'], fallback: 'Unassigned'),
      activeCount: auditNumber(json['active_count']).toInt(),
      criticalCount: auditNumber(json['critical_count']).toInt(),
      overdueCount: auditNumber(json['overdue_count']).toInt(),
    );
  }
}

/// Review dashboard summary metrics for Phase D.
class AuditReviewDashboardSummary {
  const AuditReviewDashboardSummary({
    required this.totalOpen,
    required this.criticalPriority,
    required this.highPriority,
    required this.mediumPriority,
    required this.lowPriority,
    required this.unassigned,
    required this.awaitingInfo,
    required this.underReview,
    required this.escalated,
    required this.overdue,
    required this.resolvedInPeriod,
    required this.dismissedInPeriod,
    required this.totalExposure,
    this.workload = const [],
  });

  final int totalOpen;
  final int criticalPriority;
  final int highPriority;
  final int mediumPriority;
  final int lowPriority;
  final int unassigned;
  final int awaitingInfo;
  final int underReview;
  final int escalated;
  final int overdue;
  final int resolvedInPeriod;
  final int dismissedInPeriod;
  final num totalExposure;
  final List<AuditReviewWorkload> workload;

  factory AuditReviewDashboardSummary.fromJson(Map<String, dynamic> json) {
    final metrics = auditMap(json['metrics']);
    return AuditReviewDashboardSummary(
      totalOpen: auditNumber(metrics['total_open']).toInt(),
      criticalPriority: auditNumber(metrics['critical_priority']).toInt(),
      highPriority: auditNumber(metrics['high_priority']).toInt(),
      mediumPriority: auditNumber(metrics['medium_priority']).toInt(),
      lowPriority: auditNumber(metrics['low_priority']).toInt(),
      unassigned: auditNumber(metrics['unassigned']).toInt(),
      awaitingInfo: auditNumber(metrics['awaiting_info']).toInt(),
      underReview: auditNumber(metrics['under_review']).toInt(),
      escalated: auditNumber(metrics['escalated']).toInt(),
      overdue: auditNumber(metrics['overdue']).toInt(),
      resolvedInPeriod: auditNumber(metrics['resolved_in_period']).toInt(),
      dismissedInPeriod: auditNumber(metrics['dismissed_in_period']).toInt(),
      totalExposure: auditNumber(metrics['total_exposure']),
      workload: auditRows(json['workload_by_reviewer'])
          .map((w) => AuditReviewWorkload.fromJson(w))
          .toList(),
    );
  }
}

/// Comprehensive finding review detail returned by [audit_finding_detail_v704].
class AuditFindingReviewDetail {
  const AuditFindingReviewDetail({
    required this.finding,
    this.assignee,
    this.notes = const [],
    this.history = const [],
    this.duplicates = const [],
    this.transactionStory = const [],
    this.sensitiveValuesVisible = false,
  });

  final Map<String, dynamic> finding;
  final Map<String, dynamic>? assignee;
  final List<AuditFindingNote> notes;
  final List<AuditFindingHistoryItem> history;
  final List<Map<String, dynamic>> duplicates;
  final List<Map<String, dynamic>> transactionStory;
  final bool sensitiveValuesVisible;

  String get id => auditText(finding['id']);
  String get title => auditText(finding['title']);
  String get description => auditText(finding['description']);
  String get reference => auditText(finding['entity_reference']);
  String get entityType => auditText(finding['entity_type']);
  String get entityId => auditText(finding['entity_id']);
  String get severity => auditText(finding['severity'], fallback: 'needs_review');
  String get priority => auditText(finding['priority'], fallback: 'medium');
  String get status => auditText(finding['status'], fallback: 'open');
  num get financialExposure => auditNumber(finding['financial_exposure']);
  num get riskScore => auditNumber(finding['risk_score']);
  String? get assignedTo => finding['assigned_to']?.toString();
  String? get dueDate => finding['due_date']?.toString();
  String? get duplicateGroupId => finding['duplicate_group_id']?.toString();
  bool get isDuplicate => finding['is_duplicate'] == true;
  Map<String, dynamic> get evidence => auditMap(finding['evidence']);

  // Structured risk explanation fields
  String get whatHappened =>
      auditText(evidence['what_happened'], fallback: description);
  String get whyDetected =>
      auditText(evidence['why_detected'], fallback: 'Flagged by audit risk rule');
  String get ruleName =>
      auditText(evidence['rule_name'], fallback: auditText(finding['rule_code']));
  String get investigationSteps => auditText(
    evidence['investigation_steps'],
    fallback: 'Review underlying transactional documents and reconcile balances.',
  );
  bool get isConfirmed => evidence['is_confirmed'] == true;

  factory AuditFindingReviewDetail.fromJson(Map<String, dynamic> json) {
    return AuditFindingReviewDetail(
      finding: auditMap(json['finding']),
      assignee: auditMap(json['assignee']),
      notes: auditRows(json['notes'])
          .map((n) => AuditFindingNote.fromJson(n))
          .toList(),
      history: auditRows(json['history'])
          .map((h) => AuditFindingHistoryItem.fromJson(h))
          .toList(),
      duplicates: auditRows(json['duplicates']),
      transactionStory: auditRows(json['transaction_story']),
      sensitiveValuesVisible: json['sensitive_values_visible'] == true,
    );
  }
}
