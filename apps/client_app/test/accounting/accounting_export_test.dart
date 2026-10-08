import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:client_app/services/accounting_workspace_service.dart';

ThqAccountingResult page(int offset, int total, int count) =>
    ThqAccountingResult({
      'rows': [
        for (var i = offset; i < offset + count; i++)
          {
            'journal_id': 'journal-$i',
            'lines': [
              {'account_name': 'Cash', 'debit': i + 0.5, 'credit': 0},
            ],
          },
      ],
      'columns': [],
      'total_rows': total,
      'context': {},
      'summary': [],
    });
void main() {
  final query = ThqAccountingQuery(
    report: 'journal',
    from: DateTime(2026, 10, 1),
    to: DateTime(2026, 10, 8),
    search: 'Receipt',
    filters: const {'status': 'posted'},
  );
  test(
    'exports fetch every matching page and retain full journal evidence',
    () async {
      final requests = <ThqAccountingQuery>[];
      final service = AccountingWorkspaceService(
        'tenant',
        null,
        fetch: (q) async {
          requests.add(q);
          return page(q.offset, 1201, (1201 - q.offset).clamp(0, q.limit));
        },
      );
      final result = await service.all(query);
      expect(result.rows.length, 1201);
      expect(requests.map((q) => q.offset), [0, 500, 1000]);
      expect(
        requests.every(
          (q) => q.search == 'Receipt' && q.filters['status'] == 'posted',
        ),
        isTrue,
      );
      final lines = AccountingWorkspaceService.journalLines(result);
      expect(lines.length, 1202);
      expect(lines.last[6], 1200.5);
    },
  );
  test(
    'export rejects changed totals instead of silently omitting rows',
    () async {
      final service = AccountingWorkspaceService(
        'tenant',
        null,
        fetch: (q) async => page(q.offset, q.offset == 0 ? 600 : 601, 100),
      );
      await expectLater(service.all(query), throwsStateError);
    },
  );
  testWidgets('PDF exports render complete journal tables across pages', (
    tester,
  ) async {
    final service = AccountingWorkspaceService('tenant', null);
    final data = page(0, 120, 120);
    final bytes = await service.buildPdf(
      query,
      data,
      'ABC Construction',
      'INR',
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(10000));
  });
  test(
    'export detects changed balances even when record count is unchanged',
    () async {
      final service = AccountingWorkspaceService(
        'tenant',
        null,
        fetch: (q) async {
          final data = page(q.offset, 600, 100);
          return ThqAccountingResult({
            ...data.data,
            'snapshot_token': q.offset == 0 ? 'before' : 'after',
          });
        },
      );
      await expectLater(service.all(query), throwsStateError);
    },
  );
}
