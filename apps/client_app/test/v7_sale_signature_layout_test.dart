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

var rpcReads = 0;

class SaleAppearanceStore implements ThqAppearanceStore {
  SaleAppearanceStore(this.value);
  String value;
  @override
  Future<String?> read(String key) async => value;
  @override
  Future<void> write(String key, String next) async {
    value = next;
  }
}

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
        rpcReads++;
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
          'inventory_list_products_v483' => [
            {
              'product_id': 'msand',
              'variant_id': 'msand',
              'product_name': 'M-sand fixture',
              'variant_name': 'Standard',
              'item_type': 'stock',
              'sku': 'MS-001',
              'base_unit_code': 'FT',
              'unit_code': 'FT',
              'base_unit': {
                'code': 'FT',
                'name': 'Foot',
                'allow_fractional': true,
                'quantity_step': .01,
              },
              'selling_price': 30.5,
              'cost_price': 20,
              'stock_quantity': 100,
              'tax_rate': 0,
              'tracking_mode': 'none',
              'product_status': 'active',
              'variant_status': 'active',
            },
          ],
          'pricing_resolve_v482' => {
            'unit_price': 30.5,
            'source': 'Product price',
          },
          'client_sale_quote_v630' => {
            'totals': {
              'discount': 0,
              'tax': 0,
              'before_round_off': 61,
              'automatic_round_off': 0,
              'grand_total': 61,
            },
            'classified_charge_total': 0,
          },
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

  for (final initialMode in ThqAppearance.values) {
    for (final layout in [
      (const Size(1366, 900), 1.0),
      (const Size(1024, 768), 1.0),
      (const Size(640, 600), 1.0),
      (const Size(360, 800), 1.5),
    ]) {
      final (size, scale) = layout;
      testWidgets(
        'invoice draft survives UI switching and resize: ${initialMode.label} / $size / $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final appearance = ThqAppearanceController(
            appKey: 'client',
            store: SaleAppearanceStore(initialMode.name),
          );
          await appearance.load();
          addTearDown(appearance.dispose);
          await tester.pumpWidget(
            ThqAppearanceHost(
              appKey: 'client',
              controller: appearance,
              builder: (context, mode) => MaterialApp(
                themeAnimationDuration: Duration.zero,
                theme: UiDesignProfile.fallback('client')
                    .forAppearance(mode)
                    .theme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  appBar: AppBar(actions: const [ThqAppearanceButton()]),
                  body: const NewSaleScreen(
                    session: session,
                    locationId: 'fixture',
                    embedded: true,
                    initialVariantId: 'msand',
                    initialQuantity: 2,
                    initialUnitCode: 'FT',
                    initialCustomerId: 'walk-in',
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Walk-in Customer — Counter Sale'), findsOneWidget);
          expect(find.text('Customer GSTIN'), findsOneWidget);
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
          final beforeReads = rpcReads;
          final cartRow = find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_SaleLineRow',
          );
          expect(cartRow, findsOneWidget);
          expect(find.text('M-sand fixture'), findsOneWidget);
          final cartText = tester
              .widgetList<Text>(
                find.descendant(of: cartRow, matching: find.byType(Text)),
              )
              .map((widget) => widget.data)
              .toList();
          final nextMode = initialMode == ThqAppearance.v7
              ? ThqAppearance.classic
              : ThqAppearance.v7;
          final draftState = tester.state(find.byType(NewSaleScreen));
          await tester.tap(find.byType(ThqAppearanceButton));
          await tester.pumpAndSettle();
          await tester.tap(find.text('${nextMode.label} UI'));
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(NewSaleScreen)), same(draftState));
          expect(
            tester
                .widgetList<Text>(
                  find.descendant(of: cartRow, matching: find.byType(Text)),
                )
                .map((widget) => widget.data)
                .toList(),
            cartText,
          );
          expect(find.text('125'), findsOneWidget);
          expect(find.text('Keep this invoice note'), findsOneWidget);
          expect(
            rpcReads,
            beforeReads,
            reason: 'Changing UI must not reload transaction data.',
          );
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
}
