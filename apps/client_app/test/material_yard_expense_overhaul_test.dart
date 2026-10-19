import 'package:client_app/models/client_session.dart';
import 'package:client_app/widgets/load_cost_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _testSession = ClientSession(
  business: ClientBusiness(
    id: 'test-tenant-001',
    membershipId: 'test-owner',
    name: 'THQ Aggregate Yard',
    slug: 'thq-yard',
    businessType: 'material_yard',
    status: 'active',
  ),
  modules: [],
  roles: {'owner'},
  permissions: {},
  currencyCode: 'INR',
  timezone: 'Asia/Kolkata',
  locale: 'en_IN',
);

Finder _fieldByLabel(String label) => find.ancestor(
      of: find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      ),
      matching: find.byType(TextFormField),
    );

Future<void> _renderCostEditor(
  WidgetTester tester, {
  required ValueChanged<List<Map<String, dynamic>>> onChanged,
  List<Map<String, dynamic>> initialCosts = const [],
  String direction = 'outbound',
  bool internalOnly = false,
  bool monthlyStaff = false,
  String? driverId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LoadCostEditor(
            session: _testSession,
            locationId: 'yard-loc-1',
            direction: direction,
            internalOnly: internalOnly,
            driverId: driverId,
            contextData: {
              'tax_mode': 'regular_gst',
              'staff': [
                if (driverId != null)
                  {
                    'staff_id': 'staff-driver-1',
                    'driver_id': driverId,
                    'location_id': 'yard-loc-1',
                    'name': 'Ramesh Kumar',
                    'wage_basis': monthlyStaff ? 'monthly' : 'per_trip',
                    'base_rate': monthlyStaff ? 25000 : 600,
                  },
              ],
              'billing_services': [
                {
                  'variant_id': 'srv-freight-1',
                  'name': 'Transport & Delivery Charge',
                  'tax_rate': 5,
                  'gst_rate': 5,
                },
              ],
              'expense_categories': [
                {'id': 'diesel', 'name': 'Diesel'},
                {'id': 'driver_wage', 'name': 'Driver Wages'},
                {'id': 'freight', 'name': 'Freight'},
                {'id': 'loading', 'name': 'Loading Charges'},
                {'id': 'repairs', 'name': 'Repairs & Maintenance'},
              ],
            },
            costs: initialCosts,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('THQ ERP - Material Yard Expense Overhaul v7.2.4', () {
    testWidgets('LoadCostEditor opens streamlined dialog with default categories', (tester) async {
      await _renderCostEditor(
        tester,
        onChanged: (_) {},
      );

      expect(find.text('Add expense'), findsOneWidget);
      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();

      expect(find.text('Add Load Expense'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Add'), findsOneWidget);
      expect(find.text('Payment Status & Settlement'), findsOneWidget);
      expect(find.text('Not Paid Yet'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Partially Paid'), findsOneWidget);
    });

    testWidgets('Unpaid expense records total cost and creates payable with 0 payment', (tester) async {
      List<Map<String, dynamic>>? saved;
      await _renderCostEditor(
        tester,
        onChanged: (val) => saved = val,
      );

      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();

      // Enter external payee
      await tester.enterText(_fieldByLabel('External Payee / Supplier Name *'), 'Shree Transport');
      // Enter description
      await tester.enterText(_fieldByLabel('Expense / invoice description'), 'Freight for site delivery');
      // Enter quantity & rate (2 trips @ 750 = 1500)
      await tester.tap(find.text('Calculate by Trips'));
      await tester.pumpAndSettle();

      await tester.enterText(_fieldByLabel('Units / Trips *'), '2');
      await tester.enterText(_fieldByLabel('Cost per unit (editable)'), '750');

      // Select "Not Paid Yet"
      await tester.ensureVisible(find.text('Not Paid Yet'));
      await tester.tap(find.text('Not Paid Yet'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!, hasLength(1));
      final item = saved!.first;
      expect(item['payee'], 'Shree Transport');
      expect(item['quantity'], 2.0);
      expect(item['rate'], 750.0);
      expect(item['amount'], 1500.0);
      expect(item['initial_payment'], 0.0);
      expect(item['bill_amount'], 0.0);
    });

    testWidgets('Full payment calculates total amount and records 100% payment', (tester) async {
      List<Map<String, dynamic>>? saved;
      await _renderCostEditor(
        tester,
        onChanged: (val) => saved = val,
      );

      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();

      await tester.enterText(_fieldByLabel('External Payee / Supplier Name *'), 'HP Fuel Station');
      await tester.enterText(_fieldByLabel('Expense / invoice description'), 'Diesel 50 Litres');
      await tester.enterText(_fieldByLabel('Cost per unit (editable)'), '4500');

      // Select "Paid"
      await tester.ensureVisible(find.text('Paid'));
      await tester.tap(find.text('Paid'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      final item = saved!.first;
      expect(item['payee'], 'HP Fuel Station');
      expect(item['amount'], 4500.0);
      expect(item['initial_payment'], 4500.0);
      expect(item['payment_method'], 'cash');
    });

    testWidgets('Partially paid expense computes balance due accurately', (tester) async {
      List<Map<String, dynamic>>? saved;
      await _renderCostEditor(
        tester,
        onChanged: (val) => saved = val,
      );

      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();

      await tester.enterText(_fieldByLabel('External Payee / Supplier Name *'), 'JCB Earthmovers');
      await tester.enterText(_fieldByLabel('Expense / invoice description'), 'Loading excavator rent');
      await tester.enterText(_fieldByLabel('Cost per unit (editable)'), '5000');

      // Select "Partially Paid" and enter 2000
      await tester.ensureVisible(find.text('Partially Paid'));
      await tester.tap(find.text('Partially Paid'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(_fieldByLabel('Pay on load confirmation'));
      await tester.enterText(_fieldByLabel('Pay on load confirmation'), '2000');
      await tester.pumpAndSettle();

      expect(find.textContaining('Due: INR 3000.00'), findsOneWidget);

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      final item = saved!.first;
      expect(item['amount'], 5000.0);
      expect(item['initial_payment'], 2000.0);
    });

    testWidgets('Monthly staff salary allocation rejects separate load payment and keeps load cost', (tester) async {
      List<Map<String, dynamic>>? saved;
      await _renderCostEditor(
        tester,
        monthlyStaff: true,
        driverId: 'drv-monthly-1',
        onChanged: (val) => saved = val,
      );

      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();

      expect(find.text('Already covered by salary'), findsOneWidget);
      expect(find.text('Extra payment owed to staff'), findsOneWidget);

      await tester.enterText(_fieldByLabel('Cost per unit (editable)'), '800');
      // Attempt to pay 200 on salary allocation
      await tester.ensureVisible(_fieldByLabel('Pay on load confirmation'));
      await tester.enterText(_fieldByLabel('Pay on load confirmation'), '200');

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(saved, isNull);
      expect(find.textContaining('Salary allocation requires monthly staff and no separate payment'), findsOneWidget);

      // Reset payment to 0 and save
      await tester.enterText(_fieldByLabel('Pay on load confirmation'), '0');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      final item = saved!.first;
      expect(item['staff_mode'], 'salary_allocation');
      expect(item['amount'], 800.0);
      expect(item['initial_payment'], 0.0);
    });

    testWidgets('Monthly staff extra wage option permits paying per-trip incentive', (tester) async {
      List<Map<String, dynamic>>? saved;
      await _renderCostEditor(
        tester,
        monthlyStaff: true,
        driverId: 'drv-monthly-1',
        onChanged: (val) => saved = val,
      );

      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();

      // Switch to Extra payment owed to staff
      await tester.ensureVisible(find.text('Extra payment owed to staff'));
      await tester.tap(find.text('Extra payment owed to staff'));
      await tester.pumpAndSettle();

      await tester.enterText(_fieldByLabel('Cost per unit (editable)'), '500');
      await tester.ensureVisible(find.text('Paid'));
      await tester.tap(find.text('Paid'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      final item = saved!.first;
      expect(item['staff_mode'], 'extra_wage');
      expect(item['amount'], 500.0);
      expect(item['initial_payment'], 500.0);
    });

    testWidgets('Outbound customer charge validates billing service and preserves margin', (tester) async {
      List<Map<String, dynamic>>? saved;
      await _renderCostEditor(
        tester,
        direction: 'outbound',
        internalOnly: false,
        onChanged: (val) => saved = val,
      );

      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();

      await tester.enterText(_fieldByLabel('External Payee / Supplier Name *'), 'FastTrack Logistics');
      await tester.enterText(_fieldByLabel('Expense / invoice description'), 'Site delivery');
      await tester.enterText(_fieldByLabel('Cost per unit (editable)'), '1200');

      // Enter customer charge 1500 (margin 300) without selecting service
      await tester.ensureVisible(_fieldByLabel('Amount charged to customer before GST'));
      await tester.enterText(_fieldByLabel('Amount charged to customer before GST'), '1500');

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Error shown: service tax classification required
      expect(saved, isNull);
      expect(find.textContaining('Select or create the service'), findsOneWidget);

      // Select service
      await tester.ensureVisible(find.text('Select charge service'));
      await tester.tap(find.text('Select charge service'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Transport & Delivery Charge').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      final item = saved!.first;
      expect(item['amount'], 1200.0);
      expect(item['bill_amount'], 1500.0);
      expect(item['billing_variant_id'], 'srv-freight-1');
    });

    testWidgets('Editing an existing expense line pre-fills all data and permits updating', (tester) async {
      List<Map<String, dynamic>>? saved;
      final existingCost = {
        'id': 'cost-line-999',
        'cost_kind': 'freight',
        'category_id': 'freight',
        'category_name': 'Freight',
        'description': 'Quarry transport',
        'payee': 'Express Carriers',
        'quantity': 1.0,
        'rate': 2200.0,
        'amount': 2200.0,
        'bill_amount': 0.0,
        'billing_variant_id': '',
        'initial_payment': 1000.0,
        'payment_method': 'bank',
        'payment_reference': 'NEFT-12345',
        'receipt_reference': 'VOUCH-789',
        'notes': 'Advance given to driver',
      };

      await _renderCostEditor(
        tester,
        initialCosts: [existingCost],
        onChanged: (val) => saved = val,
      );

      // Verify card rendered
      expect(find.textContaining('Quarry transport'), findsOneWidget);
      expect(find.textContaining('Express Carriers'), findsOneWidget);

      // Tap Edit (tap the ListTile containing Quarry transport)
      await tester.tap(find.textContaining('Quarry transport'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Load Expense'), findsOneWidget);
      expect(tester.widget<TextFormField>(_fieldByLabel('Cost per unit (editable)')).controller!.text, '2200');
      expect(tester.widget<TextFormField>(_fieldByLabel('Pay on load confirmation')).controller!.text, '1000');

      // Update rate to 2500
      await tester.enterText(_fieldByLabel('Cost per unit (editable)'), '2500');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      final updated = saved!.first;
      expect(updated['id'], 'cost-line-999');
      expect(updated['amount'], 2500.0);
      expect(updated['initial_payment'], 1000.0);
      expect(updated['receipt_reference'], 'VOUCH-789');
      expect(updated['notes'], 'Advance given to driver');
    });
  });
}
