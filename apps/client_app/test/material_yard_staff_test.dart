import 'dart:async';

import 'package:client_app/models/client_session.dart';
import 'package:client_app/models/sale_detail.dart';
import 'package:client_app/services/invoice_pdf_service.dart';
import 'package:client_app/widgets/load_cost_editor.dart';
import 'package:client_app/widgets/operational_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = ClientSession(
  business: ClientBusiness(
    id: 'test-tenant',
    membershipId: 'test-owner',
    name: 'THQ Yard',
    slug: 'test-yard',
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

Finder _field(String label) => find.ancestor(
  of: find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  ),
  matching: find.byType(TextFormField),
);

Future<void> _openForm(
  WidgetTester tester,
  Future<void> Function(Map<String, dynamic>) save, {
  ValueChanged<bool?>? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showOperationalForm(
              context,
              title: 'Record payment',
              initial: const {
                'request_id': 'stable-request',
                'load_id': 'saved-load',
                'amount': 10,
                'date': '2026-10-04',
                'reference': 'BANK-REF-1',
                'notes': 'Keep all entered notes',
              },
              fields: const [
                OperationalField(
                  'amount',
                  'Amount',
                  number: true,
                  required: true,
                ),
                OperationalField('date', 'Date', date: true, required: true),
                OperationalField('reference', 'Reference'),
                OperationalField('notes', 'Notes', lines: 2),
              ],
              onSave: save,
            ).then((result) => onResult?.call(result)),
            child: const Text('Open payment'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open payment'));
  await tester.pumpAndSettle();
}

Future<void> _openCost(
  WidgetTester tester, {
  required bool monthly,
  required ValueChanged<List<Map<String, dynamic>>> changed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LoadCostEditor(
            session: _session,
            locationId: 'yard',
            direction: 'outbound',
            driverId: 'driver',
            contextData: {
              'tax_mode': 'non_gst',
              'staff': [
                {
                  'staff_id': 'staff',
                  'driver_id': 'driver',
                  'location_id': 'yard',
                  'name': 'Linked driver',
                  'wage_basis': monthly ? 'monthly' : 'per_trip',
                  'base_rate': monthly ? 30000 : 700,
                },
              ],
              'billing_services': <dynamic>[],
            },
            costs: const [],
            onChanged: changed,
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Add expense'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('payments reject negative, non-finite and invalid dates', (
    tester,
  ) async {
    var calls = 0;
    await _openForm(tester, (_) async => calls++);
    for (final invalid in ['-1', 'NaN', 'Infinity']) {
      await tester.enterText(_field('Amount'), invalid);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a finite, non-negative number'), findsOneWidget);
      expect(calls, 0);
    }
    await tester.enterText(_field('Amount'), '10');
    await tester.enterText(_field('Date'), '2026-02-30');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid date as YYYY-MM-DD'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets(
    'saving blocks duplicate submissions and preserves entered evidence',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      Map<String, dynamic>? saved;
      await _openForm(tester, (data) async {
        calls++;
        saved = data;
        await pending.future;
      });
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Record payment'), findsOneWidget);
      expect(calls, 1);
      expect(saved, containsPair('request_id', 'stable-request'));
      expect(saved, containsPair('load_id', 'saved-load'));
      expect(saved, containsPair('reference', 'BANK-REF-1'));
      expect(saved, containsPair('notes', 'Keep all entered notes'));
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Record payment'), findsNothing);
    },
  );

  testWidgets(
    'failed payment keeps evidence and the same request ID for retry',
    (tester) async {
      final attempts = <Map<String, dynamic>>[];
      await _openForm(tester, (data) async {
        attempts.add(data);
        if (attempts.length == 1) throw StateError('Temporary save failure');
      });
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Temporary save failure'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(attempts, hasLength(2));
      expect(attempts[1], attempts[0]);
    },
  );

  testWidgets('payment form fits a small screen without layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openForm(tester, (_) async {});
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('saved form stays valid throughout its closing animation', (
    tester,
  ) async {
    bool? result;
    Map<String, dynamic>? saved;
    await _openForm(
      tester,
      (data) async => saved = data,
      onResult: (value) => result = value,
    );
    await tester.enterText(_field('Reference'), 'FOCUSED-PAYMENT');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(result, isTrue);
    expect(saved, containsPair('reference', 'FOCUSED-PAYMENT'));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('Record payment'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focused form can cancel and reopen without stale controllers', (
    tester,
  ) async {
    var calls = 0;
    bool? result;
    await _openForm(
      tester,
      (_) async => calls++,
      onResult: (value) => result = value,
    );
    for (var attempt = 0; attempt < 3; attempt++) {
      await tester.enterText(_field('Reference'), 'CANCEL-$attempt');
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(result, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.text('Record payment'), findsNothing);
      if (attempt < 2) {
        await tester.tap(find.text('Open payment'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(_field('Reference')).controller!.text,
          'BANK-REF-1',
        );
      }
    }
    expect(calls, 0);
  });

  testWidgets('pending save does not update a removed form', (tester) async {
    final pending = Completer<void>();
    await _openForm(tester, (_) => pending.future);
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.completeError(StateError('Save completed after navigation'));
    await tester.pumpAndSettle();
    expect(find.text('Record payment'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('linked per-trip driver wage defaults and saves cost details', (
    tester,
  ) async {
    List<Map<String, dynamic>>? saved;
    await _openCost(tester, monthly: false, changed: (value) => saved = value);
    expect(
      tester
          .widget<TextFormField>(_field('Cost per unit (editable)'))
          .controller!
          .text,
      '700',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(saved!.single, containsPair('staff_id', 'staff'));
    expect(saved!.single, containsPair('staff_mode', 'extra_wage'));
    expect(saved!.single, containsPair('amount', 700));
    expect(saved!.single['id'], isNotEmpty);
  });

  testWidgets('monthly allocation rejects a separate load payment', (
    tester,
  ) async {
    List<Map<String, dynamic>>? saved;
    await _openCost(tester, monthly: true, changed: (value) => saved = value);
    await tester.ensureVisible(_field('Cost per unit (editable)'));
    await tester.enterText(_field('Cost per unit (editable)'), '1000');
    await tester.ensureVisible(_field('Pay on load confirmation'));
    await tester.enterText(_field('Pay on load confirmation'), '100');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(
      find.textContaining('Salary allocation requires monthly staff'),
      findsOneWidget,
    );
    await tester.enterText(_field('Pay on load confirmation'), '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved!.single, containsPair('staff_mode', 'salary_allocation'));
    expect(saved!.single, containsPair('amount', 1000));
    expect(saved!.single, containsPair('initial_payment', 0));
  });

  testWidgets('customer charge requires its invoice service classification', (
    tester,
  ) async {
    var changed = false;
    await _openCost(tester, monthly: false, changed: (_) => changed = true);
    await tester.ensureVisible(_field('Amount charged to customer before GST'));
    await tester.enterText(
      _field('Amount charged to customer before GST'),
      '900',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(changed, isFalse);
    expect(find.textContaining('Select or create the service'), findsOneWidget);
  });

  test('old invoices still load without material yard evidence', () {
    final sale = SaleDetail.fromMap(_saleData());
    expect(sale.materialLoad, isEmpty);
    expect(sale.grandTotal, 2534);
  });

  for (final paper in ['a4', '80mm', '58mm']) {
    test(
      'invoice $paper paginates extensive saved load and payment evidence',
      () async {
        final sale = SaleDetail.fromMap({
          ..._saleData(),
          'material_load': {
            'load_number': 'LOAD-EVIDENCE',
            'driver_name': 'Saved driver name',
            'vehicle_registration': 'KL-01-AB-1234',
            'delivery': {
              'driver_license_snapshot': 'SAVED-LICENCE',
              'delivery_address': List.filled(
                30,
                'Saved delivery location',
              ).join(' '),
              'notes': List.filled(
                400,
                'Complete delivery evidence.',
              ).join(' '),
            },
            'costs': List.generate(
              40,
              (i) => {
                'description': 'Saved load expense $i',
                'payee': 'Saved payee $i',
                'cost_kind': 'diesel',
                'quantity': 1,
                'rate': 100,
                'amount': 100,
                'bill_amount': 120,
                'paid_amount': 30,
                'outstanding': 70,
                'receipt_reference': 'RECEIPT-$i',
                'notes': 'All expense details remain on the invoice.',
              },
            ),
            'cost_payments': [
              {
                'payee': 'Saved pump',
                'amount': 30,
                'reference': 'BANK-PAYMENT',
                'payment_date': '2026-10-04',
              },
            ],
          },
        });
        final bytes = await InvoicePdfService().build(
          session: _session,
          sale: sale,
          paperType: paper,
          template: const {},
          origin: const {},
        );
        expect(bytes.length, greaterThan(2000));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(sale.materialLoad['costs'], hasLength(40));
      },
    );
  }
}

Map<String, dynamic> _saleData() => {
  'sale': {
    'sale_id': 'sale',
    'sale_number': 'INV-TEST',
    'customer_id': 'customer',
    'customer_name': 'Test customer',
    'sale_date': '2026-10-04',
    'status': 'posted',
    'subtotal': 2534,
    'taxable_total': 2534,
    'grand_total': 2534,
  },
  'items': [
    {
      'item_id': 'material',
      'variant_id': 'variant',
      'product_name': 'Edited material description',
      'unit_code': 'CFT',
      'quantity': 1,
      'unit_price': 1234,
      'taxable_value': 1234,
      'line_total': 1234,
    },
    {
      'item_id': 'service',
      'variant_id': 'service',
      'product_name': 'Driver wage and fuel charge',
      'unit_code': 'NOS',
      'quantity': 1,
      'unit_price': 1300,
      'taxable_value': 1300,
      'line_total': 1300,
    },
  ],
  'payments': <dynamic>[],
  'paid_amount': 0,
  'balance_due': 2534,
};
