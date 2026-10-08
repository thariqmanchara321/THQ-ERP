import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

ThqAccountingResult report(
  String type, {
  List<Map<String, dynamic>> rows = const [],
}) => ThqAccountingResult({
  'rows': rows,
  'columns': [
    {'key': 'reference', 'label': 'Reference', 'type': 'text'},
    {'key': 'total', 'label': 'Total', 'type': 'money'},
    {'key': 'balance', 'label': 'Balance', 'type': 'money'},
  ],
  'total_rows': rows.length,
  'summary': [],
  'alerts': [],
  'options': {
    'accounts': [
      {'id': 'cash', 'name': 'Cash', 'method': 'cash'},
    ],
    'customers': [
      {'id': 'abc', 'name': 'ABC Construction'},
    ],
    'sources': ['future_module'],
  },
  'context': {},
  'tax_mode': 'non_gst',
});
Widget workspace(ThqAccountingLoader load, {String scope = 'one'}) =>
    MaterialApp(
      home: Scaffold(
        body: ThqAccountingWorkspace(
          businessId: 'business',
          scopeKey: scope,
          scopeLabel: 'Store',
          currency: 'INR',
          load: load,
          export: (_, _) async {},
          openSource: (_) async {},
        ),
      ),
    );
Future<void> section(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(ChoiceChip, label);
  await tester.scrollUntilVisible(
    finder,
    350,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'all operational screens are present and GL asks for an account',
    (tester) async {
      await tester.pumpWidget(workspace((q) async => report(q.report)));
      await tester.pumpAndSettle();
      expect(thqAccountingSections.length, 14);
      await section(tester, 'General Ledger');
      expect(
        find.text('Choose an account or party above to see its full history.'),
        findsOneWidget,
      );
      expect(find.text('Account'), findsOneWidget);
    },
  );
  testWidgets(
    'search is debounced and older responses cannot replace newer results',
    (tester) async {
      final old = Completer<ThqAccountingResult>();
      final queries = <ThqAccountingQuery>[];
      await tester.pumpWidget(
        workspace((q) {
          queries.add(q);
          if (q.search == 'old') return old.future;
          return Future.value(
            report(
              q.report,
              rows: q.report == 'sales'
                  ? [
                      {
                        'reference': q.search.isEmpty
                            ? 'Initial sale'
                            : 'Newest sale',
                        'total': 2500,
                        'balance': 1500,
                      },
                    ]
                  : [],
            ),
          );
        }),
      );
      await tester.pumpAndSettle();
      await section(tester, 'Sales Register');
      final input = find.byType(TextField).first;
      await tester.enterText(input, 'old');
      await tester.pump(const Duration(milliseconds: 310));
      await tester.enterText(input, 'new');
      await tester.pump(const Duration(milliseconds: 310));
      await tester.pumpAndSettle();
      expect(find.text('Newest sale'), findsOneWidget);
      old.complete(
        report(
          'sales',
          rows: [
            {'reference': 'Stale sale', 'total': 1, 'balance': 1},
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Stale sale'), findsNothing);
      expect(queries.last.search, 'new');
    },
  );
  testWidgets('grouped Journal displays an unknown source and all its lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      workspace(
        (q) async => report(
          q.report,
          rows: q.report == 'journal'
              ? [
                  {
                    'journal_id': 'j1',
                    'reference': 'FUT-001',
                    'entry_number': 'JRN-001',
                    'type': 'Future module',
                    'party': 'ABC',
                    'date': '2026-10-04',
                    'status': 'posted',
                    'balance_status': 'Balanced',
                    'amount': 4250,
                    'debit': 4250,
                    'credit': 4250,
                    'lines': [
                      for (final name in [
                        'Cash',
                        'Customer Receivable',
                        'Sales Revenue',
                        'COGS',
                        'Inventory',
                      ])
                        {
                          'account_id': name,
                          'account_name': name,
                          'account_code': '100',
                          'debit': 850,
                          'credit': 850,
                        },
                    ],
                  },
                ]
              : [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await section(tester, 'Journal');
    await tester.tap(find.text('FUT-001 · Future module · ABC'));
    await tester.pumpAndSettle();
    expect(find.text('100 · Inventory'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'compact layout has no overflow and clearly explains disabled GST',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(workspace((q) async => report(q.report)));
      await tester.pumpAndSettle();
      await section(tester, 'GST Register');
      expect(
        find.text(
          'GST is not enabled for this business/period. Ordinary invoices continue normally.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
