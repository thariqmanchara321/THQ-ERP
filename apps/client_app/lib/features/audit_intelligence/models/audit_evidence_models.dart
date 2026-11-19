import '../audit_widgets.dart';

/// Represents a dataset catalog entry returned by [audit_catalog_v704].
class AuditCatalogItem {
  const AuditCatalogItem({
    required this.key,
    required this.label,
    required this.group,
    this.entity,
    this.dateColumn,
    this.dateType,
    this.isMaster = false,
    this.locationColumn,
  });

  final String key;
  final String label;
  final String group;
  final String? entity;
  final String? dateColumn;
  final String? dateType;
  final bool isMaster;
  final String? locationColumn;

  factory AuditCatalogItem.fromJson(Map<String, dynamic> json) {
    return AuditCatalogItem(
      key: auditText(json['key']),
      label: auditText(json['label']),
      group: auditText(json['group'], fallback: 'General'),
      entity: json['entity']?.toString(),
      dateColumn: json['date']?.toString(),
      dateType: json['date_type']?.toString(),
      isMaster: json['master'] == true,
      locationColumn: json['location']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'group': group,
    'entity': entity,
    'date': dateColumn,
    'date_type': dateType,
    'master': isMaster,
    'location': locationColumn,
  };
}

/// Represents an evidence row returned by [audit_evidence_v704] or [audit_related_v704].
class AuditEvidenceRecord {
  const AuditEvidenceRecord({
    required this.id,
    required this.dataset,
    required this.reference,
    this.date,
    required this.status,
    this.party,
    this.amount,
    this.quantity,
    this.location,
    this.actor,
    this.journalCount = 0,
    required this.record,
  });

  final String id;
  final String dataset;
  final String reference;
  final String? date;
  final String status;
  final String? party;
  final num? amount;
  final num? quantity;
  final String? location;
  final String? actor;
  final int journalCount;
  final Map<String, dynamic> record;

  factory AuditEvidenceRecord.fromJson(Map<String, dynamic> json) {
    return AuditEvidenceRecord(
      id: auditText(json['id']),
      dataset: auditText(json['dataset']),
      reference: auditText(json['reference']),
      date: json['date']?.toString(),
      status: auditText(json['status'], fallback: 'Recorded'),
      party: json['party']?.toString(),
      amount: json['amount'] != null ? auditNumber(json['amount']) : null,
      quantity: json['quantity'] != null ? auditNumber(json['quantity']) : null,
      location: json['location']?.toString(),
      actor: json['actor']?.toString(),
      journalCount: auditNumber(json['journal_count']).toInt(),
      record: auditMap(json['record']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'dataset': dataset,
    'reference': reference,
    'date': date,
    'status': status,
    'party': party,
    'amount': amount,
    'quantity': quantity,
    'location': location,
    'actor': actor,
    'journal_count': journalCount,
    'record': record,
  };
}

/// A paginated envelope of evidence records returned by [audit_evidence_v704].
class AuditEvidencePage {
  const AuditEvidencePage({
    required this.dataset,
    required this.rows,
    required this.totalRows,
    this.snapshotToken,
    this.periodBasis,
    this.sensitiveValuesVisible = false,
    this.generatedAt,
  });

  final String dataset;
  final List<AuditEvidenceRecord> rows;
  final int totalRows;
  final String? snapshotToken;
  final String? periodBasis;
  final bool sensitiveValuesVisible;
  final String? generatedAt;

  factory AuditEvidencePage.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'] as List? ?? const [];
    return AuditEvidencePage(
      dataset: auditText(json['dataset']),
      rows: rawRows
          .whereType<Map>()
          .map((e) => AuditEvidenceRecord.fromJson(auditMap(e)))
          .toList(growable: false),
      totalRows: auditNumber(json['total_rows']).toInt(),
      snapshotToken: json['snapshot_token']?.toString(),
      periodBasis: json['period_basis']?.toString(),
      sensitiveValuesVisible: json['sensitive_values_visible'] == true,
      generatedAt: json['generated_at']?.toString(),
    );
  }
}

/// Full record detail returned by [audit_detail_v704].
class AuditEvidenceDetail {
  const AuditEvidenceDetail({
    required this.dataset,
    required this.record,
    this.links = const [],
    this.journals = const [],
    this.events = const [],
    this.warnings = const [],
    this.sensitiveValuesVisible = false,
  });

  final String dataset;
  final Map<String, dynamic> record;
  final List<AuditRecordLink> links;
  final List<AuditLinkedJournal> journals;
  final List<AuditCapturedEvent> events;
  final List<String> warnings;
  final bool sensitiveValuesVisible;

  factory AuditEvidenceDetail.fromJson(Map<String, dynamic> json) {
    final rawLinks = json['links'] as List? ?? const [];
    final rawJournals = json['journals'] as List? ?? const [];
    final rawEvents = json['events'] as List? ?? const [];
    final rawWarnings = json['warnings'] as List? ?? const [];

    return AuditEvidenceDetail(
      dataset: auditText(json['dataset']),
      record: auditMap(json['record']),
      links: rawLinks
          .whereType<Map>()
          .map((e) => AuditRecordLink.fromJson(auditMap(e)))
          .toList(growable: false),
      journals: rawJournals
          .whereType<Map>()
          .map((e) => AuditLinkedJournal.fromJson(auditMap(e)))
          .toList(growable: false),
      events: rawEvents
          .whereType<Map>()
          .map((e) => AuditCapturedEvent.fromJson(auditMap(e)))
          .toList(growable: false),
      warnings: rawWarnings.map((e) => e.toString()).toList(growable: false),
      sensitiveValuesVisible: json['sensitive_values_visible'] == true,
    );
  }
}

/// Link or relationship pointing to another evidence record or related records set.
class AuditRecordLink {
  const AuditRecordLink({
    required this.dataset,
    required this.label,
    required this.relation,
    this.recordId,
    this.matchKey,
    this.matchValue,
    this.count = 1,
  });

  final String dataset;
  final String label;
  final String relation;
  final String? recordId;
  final String? matchKey;
  final String? matchValue;
  final int count;

  bool get isParent => recordId != null && recordId!.isNotEmpty;
  bool get isChild => matchKey != null && matchKey!.isNotEmpty;

  factory AuditRecordLink.fromJson(Map<String, dynamic> json) {
    return AuditRecordLink(
      dataset: auditText(json['dataset']),
      label: auditText(json['label']),
      relation: auditText(json['relation']),
      recordId: json['record_id']?.toString(),
      matchKey: json['match_key']?.toString(),
      matchValue: json['match_value']?.toString(),
      count: auditNumber(json['count']).toInt(),
    );
  }
}

/// Accounting journal entry linked to an evidence record.
class AuditLinkedJournal {
  const AuditLinkedJournal({
    required this.id,
    required this.entryNumber,
    this.date,
    required this.status,
    this.sourceType,
    this.reversalOf,
  });

  final String id;
  final String entryNumber;
  final String? date;
  final String status;
  final String? sourceType;
  final String? reversalOf;

  factory AuditLinkedJournal.fromJson(Map<String, dynamic> json) {
    return AuditLinkedJournal(
      id: auditText(json['id']),
      entryNumber: auditText(json['entry_number']),
      date: json['date']?.toString(),
      status: auditText(json['status'], fallback: 'posted'),
      sourceType: json['source_type']?.toString(),
      reversalOf: json['reversal_of']?.toString(),
    );
  }
}

/// An audit event captured by transaction story or historical baseline.
class AuditCapturedEvent {
  const AuditCapturedEvent({
    required this.dataset,
    required this.label,
    required this.recordId,
    this.date,
    this.actor,
    required this.quality,
  });

  final String dataset;
  final String label;
  final String recordId;
  final String? date;
  final String? actor;
  final String quality;

  bool get isRecordedEvent => quality == 'Recorded event';
  bool get isHistoricalBaseline => quality == 'Historical baseline';

  factory AuditCapturedEvent.fromJson(Map<String, dynamic> json) {
    return AuditCapturedEvent(
      dataset: auditText(json['dataset']),
      label: auditText(json['label']),
      recordId: auditText(json['record_id']),
      date: json['date']?.toString(),
      actor: json['actor']?.toString(),
      quality: auditText(json['quality'], fallback: 'Recorded event'),
    );
  }
}
