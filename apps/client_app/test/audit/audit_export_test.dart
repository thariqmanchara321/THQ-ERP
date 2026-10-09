import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:client_app/features/audit_intelligence/audit_intelligence_service.dart';

class PagedAudit extends AuditIntelligenceService {
  PagedAudit({this.changeSnapshot = false, this.emptyPage = false});
  final bool changeSnapshot, emptyPage;
  final offsets = <int>[];
  @override
  Future<Map<String, dynamic>> workspace({
    required String tenantId,
    required String view,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String query = '',
    String severity = '',
    String status = '',
    String sort = 'date',
    bool descending = true,
    int offset = 0,
    String sourceType = '',
  }) async {
    offsets.add(offset);
    expect(tenantId, 'tenant');
    expect(locationId, 'store');
    expect(query, 'filter');
    expect(status, 'active');
    return {
      'total_rows': 51,
      'snapshot_token': offset > 0 && changeSnapshot ? 'changed' : 'stable',
      'rows': offset == 0
          ? List.generate(
              50,
              (i) => {
                'reference': i == 0 ? '=HYPERLINK("x")' : 'R$i',
                'value': -12.5,
              },
            )
          : emptyPage
          ? []
          : [
              {'reference': 'Last, "quoted"', 'value': 0},
            ],
    };
  }
}

Future<List<int>> export(PagedAudit service) => service.workspaceExportCsv(
  tenantId: 'tenant',
  view: 'findings',
  from: DateTime(2026, 9),
  to: DateTime(2026, 10),
  locationId: 'store',
  query: 'filter',
  status: 'active',
  columns: {'reference': 'Reference', 'value': 'Amount'},
);
void main() {
  test(
    'CSV includes every page, escaped strings, real negative numbers and BOM',
    () async {
      final service = PagedAudit();
      final bytes = await export(service);
      expect(bytes.take(3), [239, 187, 191]);
      final csv = utf8.decode(bytes.skip(3).toList());
      expect(service.offsets, [0, 50]);
      expect(csv.split('\r\n').length, 52);
      expect(csv, contains('"\'=HYPERLINK(""x"")"'));
      expect(csv, contains('"-12.5"'));
      expect(csv, contains('"Last, ""quoted"""'));
    },
  );
  test('CSV rejects changes across pages', () async {
    await expectLater(
      export(PagedAudit(changeSnapshot: true)),
      throwsStateError,
    );
  });
  test('CSV rejects an incomplete page', () async {
    await expectLater(export(PagedAudit(emptyPage: true)), throwsStateError);
  });
}
