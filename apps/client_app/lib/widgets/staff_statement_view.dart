import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
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
          ThqResponsiveTable(
            columns: const [
              ThqResponsiveColumn(title: 'Date', flex: 2),
              ThqResponsiveColumn(title: 'Document', flex: 2),
              ThqResponsiveColumn(title: 'Store / description', flex: 3),
              ThqResponsiveColumn(title: 'Earnings', flex: 2, isNumeric: true),
              ThqResponsiveColumn(title: 'Payments', flex: 2, isNumeric: true),
              ThqResponsiveColumn(title: 'Running balance', flex: 2, isNumeric: true),
            ],
            rows: ledger
                .map(
                  (row) => ThqResponsiveRow(
                    cardTitle: Text(
                      '${s.text('document_reference', row['document_reference'])} • ${s.text('date', row['date'])}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    cardFields: [
                      ('Store/Desc', '${row['location_name'] ?? ''} ${row['description'] ?? ''}'),
                      ('Earnings', s.text('earning', row['earning'])),
                      ('Payments', s.text('payment', row['payment'])),
                      ('Balance', s.text('balance', row['balance'])),
                    ],
                    cells: [
                      Text(s.text('date', row['date']), style: const TextStyle(fontSize: 12)),
                      Text(
                        s.text('document_reference', row['document_reference']),
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                      ),
                      Text(
                        '${row['location_name'] ?? ''}\n${row['description'] ?? ''}',
                        style: const TextStyle(fontSize: 11.5),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(s.text('earning', row['earning']), style: const TextStyle(fontSize: 12)),
                      Text(s.text('payment', row['payment']), style: const TextStyle(fontSize: 12)),
                      Text(
                        s.text('balance', row['balance']),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ],
                    onTap: () => RecordPreview.show(
                      context,
                      title: 'Staff transaction',
                      record: row,
                      currency: s.currency,
                    ),
                  ),
                )
                .toList(),
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
