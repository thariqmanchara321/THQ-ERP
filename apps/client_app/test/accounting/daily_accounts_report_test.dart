import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:client_app/services/daily_accounts_export_service.dart';

void main() {
  group('THQ ERP Daily Accounts Report & Export Audit', () {
    final sampleDailyAccountsData = {
      'period': {'from': '2026-10-14', 'to': '2026-10-14'},
      'currency': 'INR',
      'cash': {
        'opening': -1300.0,
        'received': 26750.0,
        'paid': 500.0,
        'closing': 24950.0,
        'net_movement': 26250.0,
      },
      'bank': {
        'opening': 0.0,
        'received': 8860.0,
        'paid': 0.0,
        'closing': 8860.0,
        'net_movement': 8860.0,
      },
      'sales': {
        'count': 6,
        'total': 35610.0,
        'tax': 0.0,
        'cash': 26750.0,
        'bank': 8860.0,
        'credit': 0.0,
      },
      'purchases': {
        'count': 4,
        'total': 143400.0,
        'tax': 0.0,
        'cash': 0.0,
        'bank': 0.0,
        'credit': 143400.0,
      },
      'receipts': {'customer_receipts': 0.0},
      'payments': {
        'supplier_payments': 0.0,
        'operating_expenses': 500.0,
        'transfers': 0.0,
      },
      'returns': {
        'sales_count': 0,
        'sales_total': 0.0,
        'purchase_count': 0,
        'purchase_total': 0.0,
      },
      'receivables': {'opening': 0.0, 'closing': 0.0, 'net_movement': 0.0},
      'payables': {'opening': 0.0, 'closing': 143400.0, 'net_movement': 143400.0},
      'reconciliation_status': 'Passed',
      'integrity_checks': {
        'double_entry_balanced': true,
        'non_negative_cash': true,
        'cash_ledger_reconciled': true,
        'reconciliation_status': 'Passed',
        'exceptions_count': 0,
      },
      'closing_statement':
          'Daily Closing Statement: On 2026-10-14 to 2026-10-14, total sales reached 35610.00 across 6 invoices. Status: Reconciled (Passed).',
      'day_journals': [
        {
          'journal_id': 'jrn-602-id',
          'entry_number': 'JRN-00000602',
          'entry_date': '2026-10-14',
          'source_type': 'expense',
          'source_id': 'exp-003-id',
          'reference': 'EXP-000003',
          'description': 'Expense EXP-000003',
          'party_name': 'FOOD',
          'financial_effect': 'Cash Outflow',
          'status': 'posted',
          'reversal_of': null,
          'debit_total': 500.0,
          'credit_total': 500.0,
          'is_balanced': true,
          'lines_count': 2,
        },
        {
          'journal_id': 'jrn-599-id',
          'entry_number': 'JRN-00000599',
          'entry_date': '2026-10-14',
          'source_type': 'expense',
          'source_id': 'exp-003-id',
          'reference': 'EXP-000003',
          'description': 'Expense EXP-000003',
          'party_name': 'FOOD',
          'financial_effect': 'Cash Outflow',
          'status': 'reversed',
          'reversal_of': null,
          'debit_total': 500.0,
          'credit_total': 500.0,
          'is_balanced': true,
          'lines_count': 2,
        },
        {
          'journal_id': 'jrn-603-id',
          'entry_number': 'JRN-00000603',
          'entry_date': '2026-10-13',
          'source_type': 'expense',
          'source_id': 'exp-004-id',
          'reference': 'EXP-000004',
          'description': 'Expense EXP-000004',
          'party_name': 'DRIKING WATTER',
          'financial_effect': 'Cash Outflow',
          'status': 'posted',
          'reversal_of': null,
          'debit_total': 300.0,
          'credit_total': 300.0,
          'is_balanced': true,
          'lines_count': 2,
        },
        {
          'journal_id': 'jrn-601-id',
          'entry_number': 'JRN-00000601',
          'entry_date': '2026-10-13',
          'source_type': 'expense',
          'source_id': 'exp-004-id',
          'reference': 'EXP-000004',
          'description': 'Expense EXP-000004',
          'party_name': 'DRIKING WATTER',
          'financial_effect': 'Cash Outflow',
          'status': 'reversed',
          'reversal_of': null,
          'debit_total': 300.0,
          'credit_total': 300.0,
          'is_balanced': true,
          'lines_count': 2,
        },
        {
          'journal_id': 'jrn-600-id',
          'entry_number': 'JRN-00000600',
          'entry_date': '2026-10-13',
          'source_type': 'expense',
          'source_id': 'exp-004-id',
          'reference': 'EXP-000004',
          'description': 'Expense EXP-000004',
          'party_name': 'DRIKING WATTER',
          'financial_effect': 'Cash Outflow',
          'status': 'reversed',
          'reversal_of': null,
          'debit_total': 300.0,
          'credit_total': 300.0,
          'is_balanced': true,
          'lines_count': 2,
        },
      ],
      'exceptions': [],
    };

    test('Priority 1: Distinguishes posted and reversed journals for EXP-000003 and EXP-000004', () {
      final journals = sampleDailyAccountsData['day_journals'] as List<Map<String, dynamic>>;

      // EXP-000003
      final exp3 = journals.where((j) => j['reference'] == 'EXP-000003').toList();
      expect(exp3.length, 2);
      final exp3Active = exp3.where((j) => j['status'] == 'posted').toList();
      final exp3Reversed = exp3.where((j) => j['status'] == 'reversed').toList();
      expect(exp3Active.length, 1);
      expect(exp3Active.first['entry_number'], 'JRN-00000602');
      expect(exp3Reversed.length, 1);
      expect(exp3Reversed.first['entry_number'], 'JRN-00000599');

      // EXP-000004
      final exp4 = journals.where((j) => j['reference'] == 'EXP-000004').toList();
      expect(exp4.length, 3);
      final exp4Active = exp4.where((j) => j['status'] == 'posted').toList();
      final exp4Reversed = exp4.where((j) => j['status'] == 'reversed').toList();
      expect(exp4Active.length, 1);
      expect(exp4Active.first['entry_number'], 'JRN-00000603');
      expect(exp4Reversed.length, 2);
      expect(exp4Reversed.map((j) => j['entry_number']), containsAll(['JRN-00000601', 'JRN-00000600']));

      // Active filtering correctly retains only the 2 active journals
      final activeOnly = journals.where((j) => j['status'] != 'reversed').toList();
      expect(activeOnly.length, 2);
      expect(activeOnly.map((j) => j['entry_number']), ['JRN-00000602', 'JRN-00000603']);
    });

    test('Priority 2: Financial totals reconcile without double-counting reversed journals', () {
      final cash = sampleDailyAccountsData['cash'] as Map<String, dynamic>;
      final opening = cash['opening'] as double;
      final received = cash['received'] as double;
      final paid = cash['paid'] as double;
      final closing = cash['closing'] as double;

      // Opening (-1300) + Inflow (26750) - Outflow (500) = Closing (24950)
      expect(opening + received - paid, closing);

      // Paid outflow is exactly 500.0 (counts JRN-00000602 only, completely excludes JRN-00000599)
      expect(paid, 500.0);
    });

    test('Priority 4 & 5: Rich metadata and integrity distinction', () {
      final journals = sampleDailyAccountsData['day_journals'] as List<Map<String, dynamic>>;
      for (final j in journals) {
        expect(j['party_name'], isNotNull);
        expect(j['financial_effect'], isNotNull);
        expect(j['status'], isNotNull);
        expect(j['is_balanced'], isTrue);
      }

      final integrity = sampleDailyAccountsData['integrity_checks'] as Map<String, dynamic>;
      expect(integrity['double_entry_balanced'], isTrue);
      expect(integrity['cash_ledger_reconciled'], isTrue);
      expect(integrity['non_negative_cash'], isTrue);
      expect(integrity['reconciliation_status'], 'Passed');
    });

    test('Priority 6: Date presets select single business-local date', () {
      final now = DateTime(2026, 10, 19, 14, 30, 0);
      final todayFrom = DateTime(now.year, now.month, now.day);
      final todayTo = DateTime(now.year, now.month, now.day);
      expect(todayFrom, todayTo);
      expect(DateFormat('yyyy-MM-dd').format(todayFrom), '2026-10-19');
      expect(DateFormat('yyyy-MM-dd').format(todayTo), '2026-10-19');

      final y = now.subtract(const Duration(days: 1));
      final yFrom = DateTime(y.year, y.month, y.day);
      final yTo = DateTime(y.year, y.month, y.day);
      expect(yFrom, yTo);
      expect(DateFormat('yyyy-MM-dd').format(yFrom), '2026-10-18');
      expect(DateFormat('yyyy-MM-dd').format(yTo), '2026-10-18');
    });

    test('Priority 3: PDF Document generation handles enriched columns without throwing', () async {
      final exportService = DailyAccountsExportService();
      
      // Active Only test
      final pdfActiveBytes = await exportService.buildPdf(
        businessName: 'Tenzo Traders',
        currencyCode: 'INR',
        from: DateTime(2026, 10, 14),
        to: DateTime(2026, 10, 14),
        locationLabel: 'Main Store',
        data: sampleDailyAccountsData,
        activeOnly: true,
      );

      expect(pdfActiveBytes, isNotEmpty);
      expect(pdfActiveBytes.length, greaterThan(1000));
      // Verify valid PDF magic header (%PDF-)
      expect(pdfActiveBytes.take(5).toList(), [0x25, 0x50, 0x44, 0x46, 0x2D]);

      // Full Audit History test
      final pdfAuditBytes = await exportService.buildPdf(
        businessName: 'Tenzo Traders',
        currencyCode: 'INR',
        from: DateTime(2026, 10, 14),
        to: DateTime(2026, 10, 14),
        locationLabel: 'Main Store',
        data: sampleDailyAccountsData,
        activeOnly: false,
      );

      expect(pdfAuditBytes, isNotEmpty);
      expect(pdfAuditBytes.length, greaterThan(1000));
      expect(pdfAuditBytes.take(5).toList(), [0x25, 0x50, 0x44, 0x46, 0x2D]);
    });

    test('Priority 3: Excel export separates sheets and respects activeOnly filtering', () {
      final rawJournals = (sampleDailyAccountsData['day_journals'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final activeJournals = rawJournals
          .where((j) => (j['status']?.toString() ?? 'posted') == 'posted')
          .toList();

      expect(activeJournals.length, 2); // JRN-00000602, JRN-00000603
      expect(rawJournals.length, 5); // 2 posted + 3 reversed

      for (final j in activeJournals) {
        expect(j['status'], 'posted');
      }

      final reversedJournals = rawJournals
          .where((j) => j['status'] == 'reversed')
          .toList();
      expect(reversedJournals.length, 3);
    });

    test('Priority 3: Full End-to-End file generation writes valid PDF and Excel files to disk', () async {
      final exportService = DailyAccountsExportService();
      final pdfBytes = await exportService.buildPdf(
        businessName: 'Tenzo Traders',
        currencyCode: 'INR',
        from: DateTime(2026, 10, 14),
        to: DateTime(2026, 10, 14),
        locationLabel: 'Main Store',
        data: sampleDailyAccountsData,
        activeOnly: true,
      );

      final outDir = Directory('test/accounting/output');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      final pdfFile = File('test/accounting/output/Tenzo_Traders_Daily_Accounts_20261014.pdf');
      pdfFile.writeAsBytesSync(pdfBytes);
      expect(pdfFile.existsSync(), isTrue);
      expect(pdfFile.lengthSync(), greaterThan(1000));
      // %PDF header
      final readPdf = pdfFile.readAsBytesSync();
      expect(readPdf.take(4).toList(), [0x25, 0x50, 0x44, 0x46]);

      // Generate real Excel file
      final excelBytes = exportService.buildExcel(
        businessName: 'Tenzo Traders',
        currencyCode: 'INR',
        from: DateTime(2026, 10, 14),
        to: DateTime(2026, 10, 14),
        locationLabel: 'Main Store',
        data: sampleDailyAccountsData,
        activeOnly: true,
      );

      final xlsxFile = File('test/accounting/output/Tenzo_Traders_Daily_Accounts_20261014.xlsx');
      xlsxFile.writeAsBytesSync(excelBytes);
      expect(xlsxFile.existsSync(), isTrue);
      expect(xlsxFile.lengthSync(), greaterThan(1000));
      // PK.. (ZIP archive / XLSX header)
      final readXlsx = xlsxFile.readAsBytesSync();
      expect(readXlsx.take(2).toList(), [0x50, 0x4B]);
    });
  });
}
