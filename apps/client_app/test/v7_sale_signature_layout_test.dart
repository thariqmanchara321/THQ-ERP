import 'dart:convert';

import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/sales_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// Uses Supabase's existing transport for local fixtures only.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thq_ui/thq_ui.dart';

const session = ClientSession(
  business: ClientBusiness(
    id: 'fixture',
    membershipId: 'fixture',
    name: 'THQ Traders',
    slug: 'fixture',
    businessType: 'retail',
    status: 'active',
  ),
  username: 'Cashier',
  modules: [],
  roles: {'owner'},
  permissions: {},
  currencyCode: 'INR',
  timezone: 'Asia/Kolkata',
  locale: 'en_IN',
  settings: {},
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : true,
        );
    FlutterSecureStorage.setMockInitialValues({
      'flexi.device_id': 'fixture',
      'flexi.device_secret': 'fixture',
      'flexi.tenant_id': 'fixture',
      'flexi.location_id': 'fixture',
    });
    await Supabase.initialize(
      url: 'https://thq-layout.invalid',
      publishableKey: 'sb_publishable_fixture',
      authOptions: const FlutterAuthClientOptions(persistSession: false),
      accessToken: () async => null,
      httpClient: MockClient((request) async {
        final rpc = request.url.path.split('/').last;
        final Object response = switch (rpc) {
          'customers_list_v621' => [
            {
              'id': 'walk-in',
              'name': 'Walk-in Customer',
              'public_id': 'CUS-0000001',
              'is_walk_in': true,
              'status': 'active',
            },
          ],
          'inventory_list_products_v483' => [],
          'sales_additional_charges_enabled_v611' => true,
          'sales_charge_catalog_list_pos_v610' => {'charges': []},
          'sales_invoice_context_v632' => {'tax_mode': 'gst_registered'},
          'payment_methods_list_v522' => [
            {
              'code': 'cash',
              'display_name': 'Cash',
              'ledger_account_id': 'fixture',
            },
          ],
          _ => throw StateError(
            'Unexpected RPC in read-only layout test: $rpc',
          ),
        };
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  for (final layout in [
    (const Size(1366, 900), 1.0),
    (const Size(1024, 768), 1.0),
    (const Size(640, 600), 1.0),
    (const Size(360, 800), 1.5),
  ]) {
    final (size, scale) = layout;
    testWidgets(
      'invoice layout and form state survive resize at $size / $scale',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThqV7Theme.desktop(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(
              body: NewSaleScreen(
                session: session,
                locationId: 'fixture',
                embedded: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Walk-in Customer — Counter Sale'), findsOneWidget);
        expect(find.text('GSTIN'), findsOneWidget);
        final cards = find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_SaleCard',
        );
        expect(cards, findsNWidgets(3));
        final details = tester.getRect(cards.at(0));
        final items = tester.getRect(cards.at(1));
        final payment = tester.getRect(cards.at(2));
        expect(items.top, greaterThan(details.bottom));
        expect(payment.top, greaterThan(items.bottom));
        expect(items.width, closeTo(details.width, .1));
        expect(payment.width, closeTo(details.width, .1));
        expect(details.width, lessThanOrEqualTo(1280));
        expect(tester.takeException(), isNull);
        final notes = find.widgetWithText(TextField, 'Notes');
        await tester.ensureVisible(notes);
        await tester.enterText(notes, 'Keep this invoice note');
        final amount = find.widgetWithText(TextField, 'Amount / Tendered');
        await tester.ensureVisible(amount);
        await tester.enterText(amount, '125');
        await tester.pump();
        tester.view.physicalSize = const Size(900, 700);
        await tester.pumpAndSettle();
        expect(find.text('Keep this invoice note'), findsOneWidget);
        expect(find.text('125'), findsOneWidget);
        expect(find.text('Walk-in Customer — Counter Sale'), findsOneWidget);
        await tester.ensureVisible(find.text('Print & Confirm'));
        expect(find.text('Print & Confirm').hitTestable(), findsOneWidget);
        expect(find.text('Just Confirm').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
