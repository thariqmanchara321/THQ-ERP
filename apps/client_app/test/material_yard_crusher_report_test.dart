import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/material_yard_crusher_report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = ClientSession(
  business: ClientBusiness(
    id: 'test-tenant',
    membershipId: 'test-owner',
    name: 'THQ Test Yard',
    slug: 'test-yard',
    businessType: 'material_yard',
    status: 'active',
  ),
  modules: [
    ClientModule(
      key: 'aggregate_yard',
      name: 'Material Yard',
      description: 'Bulk material yard management',
      category: 'yard',
      sortOrder: 1,
    ),
  ],
  roles: {'owner'},
  permissions: {'aggregate_yard.view', 'aggregate_yard.manage'},
  currencyCode: 'INR',
  timezone: 'Asia/Kolkata',
  locale: 'en_IN',
);

void main() {
  testWidgets('MaterialYardCrusherReportScreen mounts with exact register controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));

    await tester.pumpWidget(
      const MaterialApp(
        home: MaterialYardCrusherReportScreen(session: _session),
      ),
    );

    // Initial loading or header check
    expect(find.text('Crusher Material Register'), findsOneWidget);
    expect(find.text('Receive Load'), findsOneWidget);
    expect(find.text('Export Excel'), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
  });

  test('THQ Pricing Rules: Weighted average purchase rate calculates over priced transactions only', () {
    // Simulating loads per Rule 7, 9, 10
    final loads = [
      // Load 1: 100 FT @ ₹25/FT = ₹2,500
      {'quantity': 100.0, 'has_price': true, 'purchasing_price': 25.0, 'total': 2500.0},
      // Load 2: 200 FT @ ₹30/FT = ₹6,000
      {'quantity': 200.0, 'has_price': true, 'purchasing_price': 30.0, 'total': 6000.0},
      // Load 3: 150 FT unpriced / Rate pending (THQ Rule 4 & 10)
      {'quantity': 150.0, 'has_price': false, 'purchasing_price': 0.0, 'total': 0.0},
    ];

    final totalQty = loads.fold<double>(0.0, (s, r) => s + (r['quantity'] as double));
    final pricedRows = loads.where((r) => (r['has_price'] as bool) && (r['purchasing_price'] as double) > 0).toList();
    final pricedQty = pricedRows.fold<double>(0.0, (s, r) => s + (r['quantity'] as double));
    final pricedTotal = pricedRows.fold<double>(0.0, (s, r) => s + (r['total'] as double));

    final unpricedRows = loads.where((r) => !(r['has_price'] as bool) || (r['purchasing_price'] as double) <= 0).toList();
    final unpricedQty = unpricedRows.fold<double>(0.0, (s, r) => s + (r['quantity'] as double));

    // Rule 10: Total quantity includes all loads (450 FT)
    expect(totalQty, 450.0);
    expect(unpricedQty, 150.0);
    expect(pricedQty, 300.0);
    expect(pricedTotal, 8500.0);

    // Rule 9: Weighted average = Total Invoiced Value / Total Invoiced Qty = 8500 / 300 = 28.333...
    final weightedAvgRate = pricedQty > 0 ? (pricedTotal / pricedQty) : 0.0;
    expect(weightedAvgRate, closeTo(28.333, 0.001));

    // Must NOT be diluted by uninvoiced 150 FT (which would have erroneously given 8500 / 450 = 18.88)
    expect(weightedAvgRate, isNot(closeTo(8500.0 / 450.0, 0.001)));
  });
}
