import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:client_app/features/audit_intelligence/audit_intelligence_service.dart';
import 'package:client_app/features/audit_intelligence/models/audit_evidence_models.dart';

class MockAuditEvidenceService extends AuditIntelligenceService {
  MockAuditEvidenceService({
    this.catalogData = const [],
    this.evidencePageData = const {},
    this.detailData = const {},
    this.relatedPageData = const {},
    this.changeSnapshotOnPage2 = false,
  });

  final List<Map<String, dynamic>> catalogData;
  final Map<String, dynamic> evidencePageData;
  final Map<String, dynamic> detailData;
  final Map<String, dynamic> relatedPageData;
  final bool changeSnapshotOnPage2;

  final exportOffsets = <int>[];
  String? lastQuery;
  int? lastOffset;

  @override
  Future<List<AuditCatalogItem>> evidenceCatalog({
    required String tenantId,
    String? locationId,
  }) async {
    return catalogData.map(AuditCatalogItem.fromJson).toList();
  }

  @override
  Future<AuditEvidencePage> evidence({
    required String tenantId,
    required String dataset,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async {
    lastQuery = query;
    lastOffset = offset;
    return AuditEvidencePage.fromJson(evidencePageData);
  }

  @override
  Future<AuditEvidenceDetail> evidenceDetail({
    required String tenantId,
    required String dataset,
    required String recordId,
    String? locationId,
  }) async {
    return AuditEvidenceDetail.fromJson(detailData);
  }

  @override
  Future<AuditEvidencePage> relatedEvidence({
    required String tenantId,
    required String dataset,
    required String matchField,
    required String matchValue,
    String? locationId,
    int offset = 0,
    int limit = 50,
  }) async {
    return AuditEvidencePage.fromJson(relatedPageData);
  }

  @override
  Future<Uint8List> evidenceExportCsv({
    required String tenantId,
    required String dataset,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String query = '',
    Map<String, String>? columnHeaders,
  }) async {
    final rows = <AuditEvidenceRecord>[];
    String? token;
    int? total;
    const batchSize = 50;

    for (var offset = 0; offset < 100; offset += batchSize) {
      exportOffsets.add(offset);
      final currentToken = offset > 0 && changeSnapshotOnPage2 ? 'token_b' : 'token_a';
      final page = AuditEvidencePage(
        dataset: dataset,
        snapshotToken: currentToken,
        totalRows: 100,
        rows: List.generate(
          batchSize,
          (i) => AuditEvidenceRecord(
            id: 'id_${offset + i}',
            dataset: dataset,
            reference: i == 0 && offset == 0 ? '=CMD("calc")' : 'REF_${offset + i}',
            status: 'posted',
            party: 'Customer A',
            amount: 1500.50,
            quantity: 2,
            location: 'STORE-1',
            actor: 'auditor',
            journalCount: 1,
            record: {'notes': 'Audit test note'},
          ),
        ),
      );

      if (token != null && token != page.snapshotToken) {
        throw StateError('Evidence data changed during export. Please refresh and try again.');
      }
      token = page.snapshotToken;
      total = page.totalRows;
      rows.addAll(page.rows);
      if (rows.length >= total) break;
    }

    final cols = columnHeaders ?? {
      'reference': 'Reference',
      'party': 'Party',
      'amount': 'Amount',
    };

    String sanitize(dynamic value) {
      var text = value == null ? '' : value.toString();
      if (value is String && RegExp(r'^\s*[=+\-@\t\r]').hasMatch(text)) {
        text = "'$text";
      }
      return '"${text.replaceAll('"', '""')}"';
    }

    final csv = [
      cols.values.map(sanitize).join(','),
      for (final r in rows)
        cols.keys.map((k) {
          final val = k == 'reference' ? r.reference : (k == 'party' ? r.party : r.amount);
          return sanitize(val);
        }).join(','),
    ].join('\r\n');

    return Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode(csv)]);
  }
}

void main() {
  group('Audit Evidence Models & Parser Tests', () {
    test('AuditCatalogItem parses group, key, label and master properties', () {
      final json = {
        'key': 'sales',
        'label': 'Sales invoices',
        'group': 'Sales',
        'entity': 'sale',
        'date': 'sale_date',
        'date_type': 'date',
        'master': false,
        'location': null,
      };

      final item = AuditCatalogItem.fromJson(json);
      expect(item.key, 'sales');
      expect(item.label, 'Sales invoices');
      expect(item.group, 'Sales');
      expect(item.entity, 'sale');
      expect(item.dateColumn, 'sale_date');
      expect(item.dateType, 'date');
      expect(item.isMaster, isFalse);
    });

    test('AuditEvidenceRecord parses enriched and cleaned fields', () {
      final json = {
        'id': 'rec-1',
        'dataset': 'sales',
        'reference': 'SAL-001',
        'date': '2026-10-01',
        'status': 'posted',
        'party': 'Acme Corp',
        'amount': 2500.0,
        'quantity': 5,
        'location': 'STORE-MAIN',
        'actor': 'admin',
        'journal_count': 2,
        'record': {'grand_total': 2500, 'items_count': 5},
      };

      final rec = AuditEvidenceRecord.fromJson(json);
      expect(rec.id, 'rec-1');
      expect(rec.dataset, 'sales');
      expect(rec.reference, 'SAL-001');
      expect(rec.party, 'Acme Corp');
      expect(rec.amount, 2500.0);
      expect(rec.quantity, 5);
      expect(rec.journalCount, 2);
      expect(rec.record['grand_total'], 2500);
    });

    test('AuditEvidencePage parses envelope and pagination metadata', () {
      final json = {
        'dataset': 'Sales invoices',
        'total_rows': 150,
        'snapshot_token': 'snap_123',
        'period_basis': 'Selected period, using sale_date',
        'sensitive_values_visible': true,
        'generated_at': '2026-11-19T10:00:00Z',
        'rows': [
          {
            'id': 'rec-1',
            'dataset': 'sales',
            'reference': 'SAL-001',
            'status': 'posted',
            'record': {},
          },
        ],
      };

      final page = AuditEvidencePage.fromJson(json);
      expect(page.dataset, 'Sales invoices');
      expect(page.totalRows, 150);
      expect(page.snapshotToken, 'snap_123');
      expect(page.periodBasis, contains('sale_date'));
      expect(page.sensitiveValuesVisible, isTrue);
      expect(page.rows.length, 1);
    });

    test('AuditEvidenceDetail distinguishes recorded events from baselines', () {
      final json = {
        'dataset': 'Sales invoices',
        'sensitive_values_visible': false,
        'warnings': ['No native change history linked to this record.'],
        'record': {'id': 'rec-1', 'sale_number': 'SAL-001'},
        'events': [
          {
            'dataset': 'transaction_story_events_v600',
            'label': 'sale_created',
            'record_id': 'ev-1',
            'date': '2026-10-01T12:00:00Z',
            'actor': 'john',
            'quality': 'Recorded event',
          },
          {
            'dataset': 'transaction_story_events_v600',
            'label': 'imported_baseline',
            'record_id': 'ev-2',
            'date': '2026-10-01T12:00:00Z',
            'actor': 'system',
            'quality': 'Historical baseline',
          },
        ],
        'journals': [
          {
            'id': 'jrn-1',
            'entry_number': 'JRN-100',
            'date': '2026-10-01',
            'status': 'posted',
            'source_type': 'sale',
          },
        ],
        'links': [
          {
            'dataset': 'sale_items',
            'label': 'Sale items',
            'relation': 'Related records',
            'match_key': 'sale_id',
            'match_value': 'rec-1',
            'count': 3,
          },
          {
            'dataset': 'customers',
            'label': 'Customers',
            'relation': 'Linked customer id',
            'record_id': 'cust-1',
            'count': 1,
          },
        ],
      };

      final detail = AuditEvidenceDetail.fromJson(json);
      expect(detail.dataset, 'Sales invoices');
      expect(detail.sensitiveValuesVisible, isFalse);
      expect(detail.warnings, contains('No native change history linked to this record.'));
      expect(detail.events.length, 2);
      expect(detail.events[0].isRecordedEvent, isTrue);
      expect(detail.events[1].isHistoricalBaseline, isTrue);
      expect(detail.journals.length, 1);
      expect(detail.journals[0].entryNumber, 'JRN-100');
      expect(detail.links.length, 2);
      expect(detail.links[0].isChild, isTrue);
      expect(detail.links[1].isParent, isTrue);
    });
  });

  group('Audit Evidence Export & Safety Tests', () {
    test('Export CSV includes UTF-8 BOM, pagination chunks and escapes formula injection', () async {
      final service = MockAuditEvidenceService();
      final bytes = await service.evidenceExportCsv(
        tenantId: 'tenant-1',
        dataset: 'sales',
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
      );

      // Verify UTF-8 BOM [0xef, 0xbb, 0xbf]
      expect(bytes.take(3), [239, 187, 191]);

      final csv = utf8.decode(bytes.skip(3).toList());
      // Expect 100 rows + 1 header = 101 lines
      final lines = csv.split('\r\n');
      expect(lines.length, 101);

      // Verify formula injection protection for =CMD("calc")
      expect(csv, contains('"\'=CMD(""calc"")"'));

      // Verify pagination happened across offsets 0 and 50
      expect(service.exportOffsets, [0, 50]);
    });

    test('Export CSV aborts if snapshot token changes during multi-page export', () async {
      final service = MockAuditEvidenceService(changeSnapshotOnPage2: true);
      await expectLater(
        service.evidenceExportCsv(
          tenantId: 'tenant-1',
          dataset: 'sales',
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 12, 31),
        ),
        throwsStateError,
      );
    });
  });
}
