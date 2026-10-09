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
  final picker = find.byType(DropdownMenu<String>);
  final input = find.descendant(of: picker, matching: find.byType(TextField));
  await tester.tap(input);
  await tester.enterText(input, label);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, label).last);
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
      final input = find.byKey(const ValueKey('accounting-search'));
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
  testWidgets('every report is reachable from the searchable picker', (
    tester,
  ) async {
    final queries = <ThqAccountingQuery>[];
    await tester.pumpWidget(
      workspace((q) async {
        queries.add(q);
        return report(q.report);
      }),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNothing);
    for (final entry in thqAccountingSections.entries) {
      await section(tester, entry.value);
      expect(queries.last.report, entry.key);
      expect(
        tester
            .widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>))
            .initialSelection,
        entry.key,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('dismissed report search restores the active report label', (
    tester,
  ) async {
    final queries = <ThqAccountingQuery>[];
    await tester.pumpWidget(
      workspace((q) async {
        queries.add(q);
        return report(q.report);
      }),
    );
    await tester.pumpAndSettle();
    final pickerInput = find.descendant(
      of: find.byType(DropdownMenu<String>),
      matching: find.byType(TextField),
    );
    await tester.tap(pickerInput);
    await tester.enterText(pickerInput, 'no matching report');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accounting-search')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(pickerInput).controller!.text, 'Overview');
    expect(queries.last.report, 'overview');
  });

  testWidgets('drill-down and back update the selected report', (tester) async {
    await tester.pumpWidget(
      workspace(
        (q) async => report(
          q.report,
          rows: q.report == 'overview'
              ? [
                  {
                    'label': 'Sales',
                    'target': 'sales',
                    'amount': 2500,
                    'basis': 'Period',
                  },
                ]
              : [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sales'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>))
          .initialSelection,
      'sales',
    );
    await tester.tap(find.byTooltip('Back to previous report'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>))
          .initialSelection,
      'overview',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('report switching restores searches and preserves the period', (
    tester,
  ) async {
    final queries = <ThqAccountingQuery>[];
    await tester.pumpWidget(
      workspace((q) async {
        queries.add(q);
        return report(q.report);
      }),
    );
    await tester.pumpAndSettle();
    await section(tester, 'Sales Register');
    final from = queries.last.from;
    final to = queries.last.to;
    await tester.enterText(
      find.byKey(const ValueKey('accounting-search')),
      'SAL-001',
    );
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pumpAndSettle();
    await section(tester, 'Journal');
    expect(queries.last.search, isEmpty);
    await section(tester, 'Sales Register');
    expect(queries.last.search, 'SAL-001');
    expect(queries.last.from, from);
    expect(queries.last.to, to);
  });

  testWidgets('desktop table has separate Due and Status cells and more room', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      workspace(
        (q) async => ThqAccountingResult({
          'rows': q.report == 'sales'
              ? [
                  {
                    'reference': 'SAL-001',
                    'due': 1500,
                    'payment_status': 'Partial',
                  },
                ]
              : [],
          'columns': [
            {'key': 'reference', 'label': 'Invoice', 'type': 'text'},
            {'key': 'due', 'label': 'Due', 'type': 'money'},
            {'key': 'payment_status', 'label': 'Status', 'type': 'text'},
          ],
          'total_rows': q.report == 'sales' ? 1 : 0,
        }),
      ),
    );
    await tester.pumpAndSettle();
    await section(tester, 'Sales Register');
    final due = tester.getRect(find.text('₹1500.00'));
    final status = tester.getRect(find.text('Partial'));
    expect(status.left - due.right, greaterThanOrEqualTo(12));
    expect(tester.getTopLeft(find.text('Invoice')).dy, lessThan(180));
    expect(tester.takeException(), isNull);
  });
}
