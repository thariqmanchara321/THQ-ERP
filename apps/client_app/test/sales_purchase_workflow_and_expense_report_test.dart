import 'package:client_app/models/client_session.dart';
import 'package:client_app/models/expense.dart';
import 'package:client_app/services/expense_report_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Part A — Standalone New Sale & New Purchase Configuration Tests', () {
    const baseBusiness = ClientBusiness(
      id: 'tenant-1',
      membershipId: 'mem-1',
      name: 'Tenzo Material Yard',
      slug: 'tenzo-yard',
      businessType: 'material_yard',
      status: 'active',
    );

    test('Defaults to enabled (true) when tenant settings are absent', () {
      const session = ClientSession(
        business: baseBusiness,
        modules: [],
        roles: {'owner'},
        permissions: {},
        currencyCode: 'INR',
        timezone: 'Asia/Kolkata',
        locale: 'en_IN',
        canViewAllLocations: true,
      );

      expect(session.showStandaloneNewSale, isTrue);
      expect(session.showStandaloneNewPurchase, isTrue);
      expect(session.preferredTransactionEntry, equals('standard'));
    });

    test('Respects independent disable of standalone New Sale for Material Yard', () {
      final session = ClientSession(
        business: baseBusiness,
        modules: const [],
        roles: const {'owner'},
        permissions: const {},
        currencyCode: 'INR',
        timezone: 'Asia/Kolkata',
        locale: 'en_IN',
        canViewAllLocations: true,
        settings: {
          'sales_purchases': {
            'show_standalone_new_sale': false,
            'show_standalone_new_purchase': true,
            'preferred_transaction_entry': 'material_yard',
          },
        },
      );

      expect(session.showStandaloneNewSale, isFalse);
      expect(session.showStandaloneNewPurchase, isTrue);
      expect(session.preferredTransactionEntry, equals('material_yard'));
    });

    test('Respects independent disable of standalone New Purchase for Material Yard', () {
      final session = ClientSession(
        business: baseBusiness,
        modules: const [],
        roles: const {'owner'},
        permissions: const {},
        currencyCode: 'INR',
        timezone: 'Asia/Kolkata',
        locale: 'en_IN',
        canViewAllLocations: true,
        settings: {
          'sales_purchases': {
            'show_standalone_new_sale': true,
            'show_standalone_new_purchase': false,
            'preferred_transaction_entry': 'standard',
          },
        },
      );

      expect(session.showStandaloneNewSale, isTrue);
      expect(session.showStandaloneNewPurchase, isFalse);
      expect(session.preferredTransactionEntry, equals('standard'));
    });

    test('Both standalone actions can be disabled simultaneously while keeping registers active', () {
      final session = ClientSession(
        business: baseBusiness,
        modules: const [],
        roles: const {'owner'},
        permissions: const {},
        currencyCode: 'INR',
        timezone: 'Asia/Kolkata',
        locale: 'en_IN',
        canViewAllLocations: true,
        settings: {
          'sales_purchases': {
            'show_standalone_new_sale': false,
            'show_standalone_new_purchase': false,
            'preferred_transaction_entry': 'material_yard',
          },
        },
      );

      expect(session.showStandaloneNewSale, isFalse);
      expect(session.showStandaloneNewPurchase, isFalse);
      expect(session.preferredTransactionEntry, equals('material_yard'));
    });
  });

  group('Part B — Dynamic Expense Category Models & Deserialization Tests', () {
    test('ExpenseCategory deserializes name, active, description, and expenseCount', () {
      final raw = {
        'id': 'cat-123',
        'name': 'Diesel & Fuel',
        'active': true,
        'description': 'Direct machinery and generator fuel expenses',
        'expense_count': 14,
      };

      final cat = ExpenseCategory.fromMap(raw);
      expect(cat.id, equals('cat-123'));
      expect(cat.name, equals('Diesel & Fuel'));
      expect(cat.active, isTrue);
      expect(cat.description, equals('Direct machinery and generator fuel expenses'));
      expect(cat.expenseCount, equals(14));
    });

    test('ExpenseCategory gracefully handles null description and missing expense_count', () {
      final raw = {
        'id': 'cat-456',
        'name': 'Quarry Charges',
        'active': false,
      };

      final cat = ExpenseCategory.fromMap(raw);
      expect(cat.id, equals('cat-456'));
      expect(cat.name, equals('Quarry Charges'));
      expect(cat.active, isFalse);
      expect(cat.description, isNull);
      expect(cat.expenseCount, equals(0));
    });
  });

  group('Part C — Advanced Expense Report Engine & Accounting Reconciliation Tests', () {
    final exportService = ExpenseReportExportService();

    final testExpenses = <Map<String, dynamic>>[
      {
        'expense_id': 'exp-1',
        'expense_number': 'EXP-001',
        'expense_date': '2026-10-01',
        'category_id': 'cat-diesel',
        'category_name': 'Diesel',
        'payee': 'HP Fuel Station',
        'description': 'Truck 402 fuel',
        'amount': 5000.0,
        'tax_amount': 250.0,
        'round_off': 0.0,
        'total_amount': 5250.0,
        'payment_method': 'cash',
        'status': 'posted',
        'journals': [{'entry_number': 'JRN-101'}],
      },
      {
        'expense_id': 'exp-2',
        'expense_number': 'EXP-002',
        'expense_date': '2026-10-01',
        'category_id': 'cat-diesel',
        'category_name': 'Diesel',
        'payee': 'HP Fuel Station',
        'description': 'Truck 405 fuel',
        'amount': 3000.0,
        'tax_amount': 150.0,
        'round_off': 0.0,
        'total_amount': 3150.0,
        'payment_method': 'bank',
        'status': 'posted',
        'journals': [{'entry_number': 'JRN-102'}],
      },
      {
        'expense_id': 'exp-3',
        'expense_number': 'EXP-003',
        'expense_date': '2026-10-02',
        'category_id': 'cat-wages',
        'category_name': 'Driver Wages',
        'payee': 'Ramesh Driver',
        'description': 'Trip wage',
        'amount': 2000.0,
        'tax_amount': 0.0,
        'round_off': 0.0,
        'total_amount': 2000.0,
        'payment_method': 'cash',
        'status': 'posted',
        'journals': [{'entry_number': 'JRN-103'}],
      },
    ];

    test('Category Analysis aggregates totals, counts, and percentages accurately', () {
      final analysis = exportService.buildCategoryAnalysis(testExpenses);

      expect(analysis.length, equals(2));

      final diesel = analysis.firstWhere((c) => c['name'] == 'Diesel');
      expect(diesel['count'], equals(2));
      expect(diesel['total'], equals(8400.0)); // 5250 + 3150
      // Total expenses = 10400. Diesel % = 8400 / 10400 = 80.769%
      expect((diesel['percentage'] as double), closeTo(80.77, 0.1));

      final wages = analysis.firstWhere((c) => c['name'] == 'Driver Wages');
      expect(wages['count'], equals(1));
      expect(wages['total'], equals(2000.0));
      expect((wages['percentage'] as double), closeTo(19.23, 0.1));
    });

    test('Daily Trends groups expenses and calculates daily totals correctly', () {
      final trends = exportService.buildDailyTrends(testExpenses);

      expect(trends.length, equals(2));

      final day1 = trends.firstWhere((d) => d['date'] == '2026-10-01');
      expect(day1['count'], equals(2));
      expect(day1['total'], equals(8400.0));
      expect(day1['tax'], equals(400.0));

      final day2 = trends.firstWhere((d) => d['date'] == '2026-10-02');
      expect(day2['count'], equals(1));
      expect(day2['total'], equals(2000.0));
      expect(day2['tax'], equals(0.0));
    });

    test('Payment Breakdown classifies cash, bank, and other methods properly', () {
      final payments = exportService.buildPaymentBreakdown(testExpenses);

      final cash = payments.firstWhere((p) => p['method'] == 'cash');
      expect(cash['total'], equals(7250.0)); // 5250 + 2000
      expect(cash['count'], equals(2));

      final bank = payments.firstWhere((p) => p['method'] == 'bank');
      expect(bank['total'], equals(3150.0));
      expect(bank['count'], equals(1));
    });

    test('Accounting Reconciliation passes when all expenses have journals and match math', () {
      final (status, exceptions) = exportService.checkReconciliation(testExpenses);

      expect(status, equals('Passed'));
      expect(exceptions, isEmpty);
    });

    test('Accounting Reconciliation flags Mismatch when an expense lacks journal entries', () {
      final corruptedExpenses = List<Map<String, dynamic>>.from(testExpenses);
      corruptedExpenses.add({
        'expense_id': 'exp-bad',
        'expense_number': 'EXP-BAD',
        'expense_date': '2026-10-03',
        'category_name': 'Repairs',
        'total_amount': 1500.0,
        'amount': 1500.0,
        'tax_amount': 0.0,
        'status': 'posted',
        'journals': [], // Missing journals!
      });

      final (status, exceptions) = exportService.checkReconciliation(corruptedExpenses);

      expect(status, equals('Mismatch'));
      expect(exceptions.length, equals(1));
      expect(exceptions.first['expense_number'], equals('EXP-BAD'));
      expect(exceptions.first['note'], contains('Missing double-entry journal evidence'));
    });
  });
}
