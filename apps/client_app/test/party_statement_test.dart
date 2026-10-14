import 'package:flutter_test/flutter_test.dart';
import 'package:client_app/models/party_statement.dart';

void main() {
  group('PartyStatement Model & Calculation Tests', () {
    test('parses statement with sales, sales returns, and account receipts', () {
      final rawData = {
        'party_id': 'cust-001',
        'party_name': 'Acme Industries',
        'opening_balance': 5000.0,
        'total_debit': 15000.0,
        'total_credit': 12000.0,
        'closing_balance': 8000.0,
        'rows': [
          {
            'entry_date': '2026-10-01',
            'entry_type': 'sale',
            'reference': 'INV-00101',
            'description': 'Sales invoice',
            'debit': 10000.0,
            'credit': 0.0,
            'balance': 15000.0,
          },
          {
            'entry_date': '2026-10-03',
            'entry_type': 'sales_return',
            'reference': 'SRN-00001',
            'description': 'Sales return / Credit note (INV-00101)',
            'debit': 0.0,
            'credit': 2000.0,
            'balance': 13000.0,
          },
          {
            'entry_date': '2026-10-05',
            'entry_type': 'sale',
            'reference': 'INV-00102',
            'description': 'Sales invoice',
            'debit': 5000.0,
            'credit': 0.0,
            'balance': 18000.0,
          },
          {
            'entry_date': '2026-10-08',
            'entry_type': 'receipt',
            'reference': 'RCT-261008-000001',
            'description': 'Customer account receipt (CASH)',
            'debit': 0.0,
            'credit': 10000.0,
            'balance': 8000.0,
          },
        ],
      };

      final statement = PartyStatement.fromMap(rawData);

      expect(statement.partyId, 'cust-001');
      expect(statement.partyName, 'Acme Industries');
      expect(statement.openingBalance, 5000.0);
      expect(statement.totalDebit, 15000.0);
      expect(statement.totalCredit, 12000.0);
      expect(statement.closingBalance, 8000.0);
      expect(statement.rows.length, 4);

      // Verify row 1: Sale
      expect(statement.rows[0].type, 'sale');
      expect(statement.rows[0].reference, 'INV-00101');
      expect(statement.rows[0].debit, 10000.0);
      expect(statement.rows[0].credit, 0.0);
      expect(statement.rows[0].balance, 15000.0);

      // Verify row 2: Sales Return (Credit Note)
      expect(statement.rows[1].type, 'sales_return');
      expect(statement.rows[1].reference, 'SRN-00001');
      expect(statement.rows[1].debit, 0.0);
      expect(statement.rows[1].credit, 2000.0);
      expect(statement.rows[1].balance, 13000.0);

      // Verify row 4: Customer Account Receipt
      expect(statement.rows[3].type, 'receipt');
      expect(statement.rows[3].reference, 'RCT-261008-000001');
      expect(statement.rows[3].credit, 10000.0);
      expect(statement.rows[3].balance, 8000.0);
    });

    test('handles customer advance receipt and negative credit closing balance', () {
      final rawData = {
        'party_id': 'cust-002',
        'party_name': 'New Customer with Advance',
        'opening_balance': 0.0,
        'total_debit': 0.0,
        'total_credit': 2500.0,
        'closing_balance': -2500.0,
        'rows': [
          {
            'entry_date': '2026-10-10',
            'entry_type': 'receipt',
            'reference': 'RCT-261010-000002',
            'description': 'Customer account receipt (UPI) • Advance deposit',
            'debit': 0.0,
            'credit': 2500.0,
            'balance': -2500.0,
          },
        ],
      };

      final statement = PartyStatement.fromMap(rawData);

      expect(statement.partyId, 'cust-002');
      expect(statement.openingBalance, 0.0);
      expect(statement.totalDebit, 0.0);
      expect(statement.totalCredit, 2500.0);
      expect(statement.closingBalance, -2500.0);
      expect(statement.rows.length, 1);
      expect(statement.rows.first.balance, -2500.0);
    });

    test('handles empty statement gracefully', () {
      final statement = PartyStatement.fromMap({
        'party_id': 'cust-003',
        'party_name': 'Inactive Party',
      });

      expect(statement.partyId, 'cust-003');
      expect(statement.partyName, 'Inactive Party');
      expect(statement.openingBalance, 0.0);
      expect(statement.totalDebit, 0.0);
      expect(statement.totalCredit, 0.0);
      expect(statement.closingBalance, 0.0);
      expect(statement.rows, isEmpty);
    });
  });
}
