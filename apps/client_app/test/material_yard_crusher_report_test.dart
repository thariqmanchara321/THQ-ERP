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
}
