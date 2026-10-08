import 'package:flutter/material.dart';
import '../models/staff_statement.dart';
import '../models/record_presentation.dart';
import 'record_preview.dart';

class StaffStatementView extends StatelessWidget {
  final StaffStatement statement;
  const StaffStatementView({super.key, required this.statement});
  @override
  Widget build(BuildContext context) {
    final s = statement;
    final data = s.report;
    final ledger = s.rows('ledger');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.name, style: Theme.of(context).textTheme.titleLarge),
        SelectableText('Staff ID: ${s.staffCode} • ${s.period}'),
        if (s.data['location_scope'] != null)
          Text('${s.data['location_scope']}'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final key in [
              'opening_balance',
              'period_earnings',
              'period_payments',
              'closing_balance',
              'closing_due',
              'closing_advance',
            ])
              SizedBox(
                width: 220,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(RecordPresentation.label(key)),
                        SelectableText(
                          s.text(key, s.summary[key]),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(StaffStatement.balanceNote),
        const SizedBox(height: 12),
        Text(
          'Transaction statement (${ledger.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (ledger.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'No transactions in this period. Opening balance carries forward.',
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 24,
              columns: [
                for (final label in [
                  'Date',
                  'Document',
                  'Store / description',
                  'Earnings',
                  'Payments',
                  'Running balance',
                ])
                  DataColumn(
                    label: Text(label),
                    numeric: [
                      'Earnings',
                      'Payments',
                      'Running balance',
                    ].contains(label),
                  ),
              ],
              rows: ledger
                  .map(
                    (row) => DataRow(
                      cells: [
                        DataCell(Text(s.text('date', row['date']))),
                        DataCell(
                          Text(
                            s.text(
                              'document_reference',
                              row['document_reference'],
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '${row['location_name'] ?? ''}\n${row['description'] ?? ''}',
                          ),
                        ),
                        DataCell(Text(s.text('earning', row['earning']))),
                        DataCell(Text(s.text('payment', row['payment']))),
                        DataCell(Text(s.text('balance', row['balance']))),
                      ],
                      onSelectChanged: (_) => RecordPreview.show(
                        context,
                        title: 'Staff transaction',
                        record: row,
                        currency: s.currency,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Current balances • Due ${s.text('current_due', s.summary['current_due'])} • Advance ${s.text('current_advance', s.summary['current_advance'])}',
        ),
        const Text(
          'Current balances can include transactions after the selected period.',
        ),
        const SizedBox(height: 12),
        RecordPreview(
          record: {
            'balances_by_location': data['balances_by_location'],
            'profile': data['profile'],
            'earnings_payslips': data['earnings'],
            'payments_and_allocations': data['payments'],
            'load_allocations': data['load_allocations'],
            'history': data['history'],
          },
          currency: s.currency,
        ),
      ],
    );
  }
}
