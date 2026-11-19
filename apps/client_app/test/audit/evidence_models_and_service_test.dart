import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:client_app/features/audit_intelligence/audit_intelligence_service.dart';
import 'package:client_app/features/audit_intelligence/models/audit_evidence_models.dart';

class TestRpcAuditEvidenceService extends AuditIntelligenceService {
  TestRpcAuditEvidenceService({
    this.totalRecords = 250,
    this.pageSize = 100,
    this.changeSnapshotOnPage2 = false,
    this.changeTotalOnPage2 = false,
    this.emptyPage2 = false,
    this.shortPage2 = false,
  });

  final int totalRecords;
  final int pageSize;
  final bool changeSnapshotOnPage2;
  final bool changeTotalOnPage2;
  final bool emptyPage2;
  final bool shortPage2;

  final capturedOffsets = <int>[];
  final capturedTokens = <String>[];

  @override
  Future<dynamic> callEvidenceExportRpc({
    required String tenantId,
    required String dataset,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String query = '',
    int offset = 0,
    int limit = 100,
  }) async {
    capturedOffsets.add(offset);
    final isPage2 = offset == pageSize;

    final token = isPage2 && changeSnapshotOnPage2 ? 'token_b' : 'token_stable';
    capturedTokens.add(token);

    final total = isPage2 && changeTotalOnPage2 ? totalRecords + 10 : totalRecords;

    if (isPage2 && emptyPage2) {
      return {
        'dataset': dataset,
        'snapshot_token': token,
        'total_rows': total,
        'rows': <Map<String, dynamic>>[],
      };
    }

    int countToGenerate;
    if (isPage2 && shortPage2) {
      countToGenerate = 40; // premature end: returned 40 instead of 100 while more rows exist
    } else {
      final remaining = totalRecords - offset;
      countToGenerate = remaining > limit ? limit : remaining;
      if (countToGenerate < 0) countToGenerate = 0;
    }

    return {
      'dataset': dataset,
      'snapshot_token': token,
      'total_rows': total,
      'rows': List.generate(
        countToGenerate,
        (i) {
          final idx = offset + i;
          return {
            'id': 'id_$idx',
            'dataset': dataset,
            'reference': idx == 0 ? '=SUM(100,200)' : 'REF_$idx',
            'date': '2026-11-19',
            'status': 'posted',
            'party': 'Customer $idx',
            'amount': 100.0 + idx,
            'quantity': 1,
            'location': 'LOC-1',
            'actor': 'admin',
            'journal_count': 1,
            'record': {
              'email': idx % 2 == 0 ? '[REDACTED]' : 'user_$idx@example.com',
              'phone': '[REDACTED]',
              'notes': 'Verified row $idx',
            },
          };
        },
      ),
    };
  }
}

void main() {
  group('Audit Evidence Models & Redaction Tests', () {
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

    test('AuditEvidenceRecord parses enriched and redacted fields', () {
      final json = {
        'id': 'rec-1',
        'dataset': 'customers',
        'reference': 'CUST-001',
        'date': '2026-10-01',
        'status': 'Active',
        'party': 'Acme Corp',
        'amount': 2500.0,
        'quantity': null,
        'location': 'STORE-MAIN',
        'actor': 'admin',
        'journal_count': 0,
        'record': {
          'id': 'rec-1',
          'name': 'Acme Corp',
          'email': '[REDACTED]',
          'phone': '[REDACTED]',
          'bank_account': '[REDACTED]',
          'account_name': 'Operating Account',
        },
      };

      final rec = AuditEvidenceRecord.fromJson(json);
      expect(rec.id, 'rec-1');
      expect(rec.dataset, 'customers');
      expect(rec.reference, 'CUST-001');
      expect(rec.party, 'Acme Corp');
      expect(rec.record['email'], '[REDACTED]');
      expect(rec.record['phone'], '[REDACTED]');
      expect(rec.record['bank_account'], '[REDACTED]');
      expect(rec.record['account_name'], 'Operating Account');
    });

    test('AuditEvidencePage parses envelope and pagination metadata', () {
      final json = {
        'dataset': 'Sales invoices',
        'total_rows': 250,
        'snapshot_token': 'snap_stable_abc',
        'period_basis': 'Selected period, using sale_date',
        'sensitive_values_visible': false,
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
      expect(page.totalRows, 250);
      expect(page.snapshotToken, 'snap_stable_abc');
      expect(page.periodBasis, contains('sale_date'));
      expect(page.sensitiveValuesVisible, isFalse);
      expect(page.rows.length, 1);
    });

    test('AuditEvidenceDetail distinguishes recorded events from baselines', () {
      final json = {
        'dataset': 'Sales invoices',
        'sensitive_values_visible': false,
        'warnings': ['No native change history linked to this record.'],
        'record': {
          'id': 'rec-1',
          'sale_number': 'SAL-001',
          'customer_email': '[REDACTED]',
        },
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
      expect(detail.record['customer_email'], '[REDACTED]');
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

  group('Multi-Page Export & Consistency Tests (> 100 Records)', () {
    test('Exports 250 records across multiple pages (100/page) with stable snapshot token and BOM', () async {
      final service = TestRpcAuditEvidenceService(totalRecords: 250, pageSize: 100);
      final bytes = await service.evidenceExportCsv(
        tenantId: 'tenant-1',
        dataset: 'sales',
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
      );

      // Verify UTF-8 BOM
      expect(bytes.take(3), [239, 187, 191]);

      // Decode CSV
      final csv = utf8.decode(bytes.skip(3).toList());
      final lines = csv.split('\r\n');

      // 1 header line + 250 data lines = 251 lines
      expect(lines.length, 251);

      // Verify all pages (0, 100, 200) were requested
      expect(service.capturedOffsets, [0, 100, 200]);

      // Verify every page received a consistent snapshot token
      expect(service.capturedTokens, ['token_stable', 'token_stable', 'token_stable']);

      // Verify formula injection protection on row 0
      expect(csv, contains('"\'=SUM(100,200)"'));

      // Verify last row exists in output
      expect(csv, contains('"REF_249"'));
      expect(csv, contains('"Customer 249"'));
    });

    test('Multi-page export aborts if snapshot token changes on page 2', () async {
      final service = TestRpcAuditEvidenceService(
        totalRecords: 250,
        pageSize: 100,
        changeSnapshotOnPage2: true,
      );

      await expectLater(
        service.evidenceExportCsv(
          tenantId: 'tenant-1',
          dataset: 'sales',
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 12, 31),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Evidence data changed during export'),
          ),
        ),
      );

      // Failed after fetching page 2 (offset 100)
      expect(service.capturedOffsets, [0, 100]);
    });

    test('Multi-page export aborts if total rows changes on page 2', () async {
      final service = TestRpcAuditEvidenceService(
        totalRecords: 250,
        pageSize: 100,
        changeTotalOnPage2: true,
      );

      await expectLater(
        service.evidenceExportCsv(
          tenantId: 'tenant-1',
          dataset: 'sales',
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 12, 31),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Evidence data changed during export'),
          ),
        ),
      );
    });

    test('Multi-page export aborts if page 2 returns empty while more rows expected', () async {
      final service = TestRpcAuditEvidenceService(
        totalRecords: 250,
        pageSize: 100,
        emptyPage2: true,
      );

      await expectLater(
        service.evidenceExportCsv(
          tenantId: 'tenant-1',
          dataset: 'sales',
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 12, 31),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Incomplete evidence export from server'),
          ),
        ),
      );
    });

    test('Multi-page export aborts on premature truncated page', () async {
      final service = TestRpcAuditEvidenceService(
        totalRecords: 250,
        pageSize: 100,
        shortPage2: true,
      );

      await expectLater(
        service.evidenceExportCsv(
          tenantId: 'tenant-1',
          dataset: 'sales',
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 12, 31),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Incomplete evidence export from server: premature end of pages'),
          ),
        ),
      );
    });

    test('Export produces empty table with headers when total rows is 0', () async {
      final service = TestRpcAuditEvidenceService(totalRecords: 0, pageSize: 100);
      final bytes = await service.evidenceExportCsv(
        tenantId: 'tenant-1',
        dataset: 'sales',
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
      );

      final csv = utf8.decode(bytes.skip(3).toList());
      final lines = csv.split('\r\n');
      expect(lines.length, 1); // Only header
      expect(service.capturedOffsets, [0]);
    });
  });
}
