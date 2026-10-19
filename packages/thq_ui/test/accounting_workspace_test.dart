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
    await tester.tap(find.text('JRN-001'));
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

  testWidgets('TASK 1: compact Journal table shows default columns, explicit status and audit details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      workspace(
        (q) async => ThqAccountingResult({
          'rows': q.report == 'journal'
              ? [
                  {
                    'journal_id': 'j100',
                    'date': '2026-10-10',
                    'entry_number': 'JRN-100',
                    'source_reference': 'INV-100',
                    'reference': 'INV-100',
                    'type': 'Sale',
                    'source_type': 'sale',
                    'party': 'Acme Corp',
                    'debit': 5000,
                    'credit': 5000,
                    'status': 'Balanced',
                    'balance_status': 'Balanced',
                    'document_id': 'doc-100',
                    'created_at': '2026-10-10 10:30:00',
                    'lines': [
                      {
                        'account_id': 'acc-1',
                        'account_code': '101',
                        'account_name': 'Accounts Receivable',
                        'debit': 5000,
                        'credit': 0,
                        'description': 'Invoice INV-100',
                      },
                      {
                        'account_id': 'acc-2',
                        'account_code': '401',
                        'account_name': 'Sales Revenue',
                        'debit': 0,
                        'credit': 5000,
                        'description': 'Goods sold',
                      },
                    ],
                  },
                ]
              : [],
          'columns': [
            {'key': 'date', 'label': 'Date', 'type': 'date'},
            {'key': 'entry_number', 'label': 'Journal No.', 'type': 'text'},
            {'key': 'reference', 'label': 'Source Reference', 'type': 'text'},
            {'key': 'source_type', 'label': 'Type', 'type': 'text'},
            {'key': 'debit', 'label': 'Debit', 'type': 'money'},
            {'key': 'credit', 'label': 'Credit', 'type': 'money'},
            {'key': 'status', 'label': 'Status', 'type': 'text'},
          ],
          'summary': [
            {'label': 'Total Debit', 'value': 5000},
            {'label': 'Total Credit', 'value': 5000},
            {'label': 'Net Difference', 'value': 0},
          ],
          'total_rows': 1,
        }),
      ),
    );
    await tester.pumpAndSettle();
    await section(tester, 'Journal');

    // Default column headers
    expect(find.text('Date'), findsWidgets);
    expect(find.text('Journal No.'), findsOneWidget);
    expect(find.text('Source Reference'), findsOneWidget);
    expect(find.text('Type'), findsWidgets);
    expect(find.text('Debit'), findsWidgets);
    expect(find.text('Credit'), findsWidgets);
    expect(find.text('Status'), findsWidgets);

    // Row contents
    expect(find.text('JRN-100'), findsOneWidget);
    expect(find.text('INV-100 · Acme Corp'), findsOneWidget);
    expect(find.text('Balanced'), findsWidgets);

    // Click to expand detailed debit/credit lines
    await tester.tap(find.text('JRN-100'));
    await tester.pumpAndSettle();

    expect(find.text('101 · Accounts Receivable'), findsOneWidget);
    expect(find.text('401 · Sales Revenue'), findsOneWidget);
    expect(find.text('Balanced ✓ (DR = CR)'), findsOneWidget);
    expect(find.text('Original document'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TASK 2: compact Profit & Loss shows hierarchical rows, Gross Profit and Net Profit', (
    tester,
  ) async {
    await tester.pumpWidget(
      workspace(
        (q) async => ThqAccountingResult({
          'rows': q.report == 'profit_loss'
              ? [
                  {
                    'account_id': 'rev1',
                    'group': 'Revenue',
                    'account_name': 'Sales Revenue',
                    'amount': 25000,
                  },
                  {
                    'account_id': 'cogs1',
                    'group': 'Cost of Goods Sold',
                    'account_name': 'Cost of Materials',
                    'amount': 15000,
                  },
                  {
                    'account_id': 'exp1',
                    'group': 'Operating Expenses',
                    'account_name': 'Rent Expense',
                    'amount': 3000,
                  },
                ]
              : [],
          'columns': [
            {'key': 'group', 'label': 'Group', 'type': 'text'},
            {'key': 'account_name', 'label': 'Account', 'type': 'text'},
            {'key': 'amount', 'label': 'Amount', 'type': 'money'},
          ],
          'data': {
            'group_totals': {
              'Revenue': 25000,
              'Cost of Goods Sold': 15000,
              'Operating Expenses': 3000,
            },
          },
          'summary': [],
          'total_rows': 3,
        }),
      ),
    );
    await tester.pumpAndSettle();
    await section(tester, 'Profit & Loss');

    expect(find.text('Revenue'), findsOneWidget);
    expect(find.text('Cost of Goods Sold'), findsOneWidget);
    expect(find.text('Gross Profit'), findsOneWidget);
    expect(find.text('Operating Expenses'), findsOneWidget);
    expect(find.text('Net Profit'), findsOneWidget);

    // Account rows visible
    expect(find.text('Sales Revenue'), findsOneWidget);
    expect(find.text('Cost of Materials'), findsOneWidget);
    expect(find.text('Rent Expense'), findsOneWidget);

    // Subtotals
    expect(find.text('₹10000.00'), findsOneWidget); // Gross Profit (25000 - 15000)
    expect(find.text('₹7000.00'), findsOneWidget);  // Net Profit (10000 - 3000)
    expect(tester.takeException(), isNull);
  });

  testWidgets('TASK 2: compact Balance Sheet preserves Assets = Liabilities + Equity and displays balance check', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      workspace(
        (q) async => ThqAccountingResult({
          'rows': q.report == 'balance_sheet'
              ? [
                  {
                    'account_id': 'ast1',
                    'group': 'Assets',
                    'subgroup': 'Current Assets',
                    'account_name': 'Bank Account',
                    'amount': 20000,
                  },
                  {
                    'account_id': 'lia1',
                    'group': 'Liabilities',
                    'subgroup': 'Liabilities',
                    'account_name': 'Accounts Payable',
                    'amount': 8000,
                  },
                  {
                    'account_id': 'eq1',
                    'group': 'Equity',
                    'account_name': 'Capital',
                    'amount': 10000,
                  },
                  {
                    'account_id': 'current_earnings',
                    'group': 'Equity',
                    'account_name': 'Unclosed earnings',
                    'amount': 2000,
                  },
                ]
              : [],
          'columns': [
            {'key': 'group', 'label': 'Group', 'type': 'text'},
            {'key': 'account_name', 'label': 'Account', 'type': 'text'},
            {'key': 'amount', 'label': 'Amount', 'type': 'money'},
          ],
          'data': {
            'group_totals': {
              'Assets': 20000,
              'Liabilities': 8000,
              'Equity': 12000,
            },
          },
          'summary': [],
          'total_rows': 4,
        }),
      ),
    );
    await tester.pumpAndSettle();
    await section(tester, 'Balance Sheet');

    expect(find.text('Assets'), findsOneWidget);
    expect(find.text('Liabilities'), findsOneWidget);
    expect(find.text('Equity'), findsOneWidget);
    expect(find.text('Total Assets'), findsOneWidget);
    expect(find.text('Total Liabilities'), findsOneWidget);
    expect(find.text('Total Equity'), findsOneWidget);
    expect(find.text('Total Liabilities & Equity'), findsOneWidget);

    // Balanced indicator: Assets = Liabilities + Equity (20000 == 8000 + 12000)
    expect(find.textContaining('Assets = Liabilities + Equity'), findsOneWidget);
    expect(find.textContaining('Balanced ✓'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TASK 3: historical Paid and Due reflects report end date and Partially Paid status', (
    tester,
  ) async {
    // Mandatory scenario test:
    // Invoice 10 Oct 2026 total 10,000.
    // For report ending 16 Oct: Paid = 4,000, Due = 6,000, Status = 'Partially Paid'
    await tester.pumpWidget(
      workspace(
        (q) async => ThqAccountingResult({
          'rows': q.report == 'sales'
              ? [
                  {
                    'date': '2026-10-10',
                    'reference': 'INV-2026-001',
                    'party': 'Customer A',
                    'total': 10000,
                    'paid': 4000,
                    'due': 6000,
                    'payment_status': 'Partially Paid',
                  },
                ]
              : [],
          'columns': [
            {'key': 'date', 'label': 'Date', 'type': 'date'},
            {'key': 'reference', 'label': 'Invoice', 'type': 'text'},
            {'key': 'party', 'label': 'Customer', 'type': 'text'},
            {'key': 'total', 'label': 'Total', 'type': 'money'},
            {'key': 'paid', 'label': 'Paid', 'type': 'money'},
            {'key': 'due', 'label': 'Due', 'type': 'money'},
            {'key': 'payment_status', 'label': 'Status', 'type': 'text'},
          ],
          'summary': [
            {'label': 'Document Total', 'value': 10000},
            {'label': 'Paid through end date', 'value': 4000},
            {'label': 'Due through end date', 'value': 6000},
          ],
          'total_rows': 1,
        }),
      ),
    );
    await tester.pumpAndSettle();
    await section(tester, 'Sales Register');

    expect(find.text('INV-2026-001'), findsOneWidget);
    expect(find.text('Customer A'), findsOneWidget);
    expect(find.text('₹10000.00'), findsOneWidget);
    expect(find.text('₹4000.00'), findsOneWidget);
    expect(find.text('₹6000.00'), findsOneWidget);
    expect(find.text('Partially Paid'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
