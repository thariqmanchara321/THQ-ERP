import 'dart:convert';

import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/sales_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing transport is used with local fixtures; no live writes are permitted.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thq_ui/thq_ui.dart';

const session = ClientSession(
  business: ClientBusiness(
    id: 'fixture-fields',
    membershipId: 'fixture-fields',
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
String taxMode = 'non_gst';
bool interstate = false;
bool contextFailure = false;
final calls = <String>[];

class AppearanceStore implements ThqAppearanceStore {
  AppearanceStore(this.value);
  String value;
  @override
  Future<String?> read(String key) async => value;
  @override
  Future<void> write(String key, String next) async {
    value = next;
  }
}

void expectVisibleBounds(WidgetTester tester, Finder field, Finder viewport) {
  final bounds = tester.getRect(field);
  final visible = bounds.intersect(tester.getRect(viewport));
  expect(bounds.width, greaterThan(0));
  expect(bounds.height, greaterThan(0));
  expect(visible.width, closeTo(bounds.width, .1));
  expect(visible.height, closeTo(bounds.height, .1));
}

Future<ThqAppearanceController> showSale(
  WidgetTester tester,
  ThqAppearance mode,
  Size size,
  double scale, {
  bool named = false,
  bool withItem = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final appearance = ThqAppearanceController(
    appKey: 'client',
    store: AppearanceStore(mode.name),
  );
  await appearance.load();
  addTearDown(appearance.dispose);
  await tester.pumpWidget(
    ThqAppearanceHost(
      appKey: 'client',
      controller: appearance,
      builder: (context, value) => MaterialApp(
        themeAnimationDuration: Duration.zero,
        theme: UiDesignProfile.fallback('client').forAppearance(value).theme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(actions: const [ThqAppearanceButton()]),
          body: NewSaleScreen(
            session: session,
            locationId: 'fixture-fields',
            embedded: true,
            initialVariantId: withItem ? 'msand' : null,
            initialQuantity: withItem ? 2 : null,
            initialUnitCode: 'FT',
            initialCustomerId: named ? 'named' : 'walk-in',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return appearance;
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
      'flexi.tenant_id': 'fixture-fields',
      'flexi.location_id': 'fixture-fields',
    });
    await Supabase.initialize(
      url: 'https://thq-fields.invalid',
      publishableKey: 'sb_publishable_fixture',
      authOptions: const FlutterAuthClientOptions(persistSession: false),
      accessToken: () async => null,
      httpClient: MockClient((request) async {
        final rpc = request.url.path.split('/').last;
        calls.add(rpc);
        if (rpc == 'sales_invoice_context_v632' && contextFailure) {
          return http.Response(
            jsonEncode({
              'message': 'Complete the business GST setup before billing.',
              'code': 'P0001',
              'details': null,
              'hint': null,
            }),
            400,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        final gst = taxMode == 'gst_registered';
        final Object result = switch (rpc) {
          'customers_list_v621' => [
            {
              'id': 'walk-in',
              'name': 'Walk-in Customer',
              'public_id': 'CUS-0000001',
              'is_walk_in': true,
              'status': 'active',
            },
            {
              'id': 'named',
              'name': 'Named Customer',
              'public_id': 'CUS-0000002',
              'is_walk_in': false,
              'status': 'active',
              'tax_number': '32ABCDE1234F1Z5',
              'state': 'Kerala',
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
              'tax_rate': 18,
              'tracking_mode': 'none',
              'product_status': 'active',
              'variant_status': 'active',
            },
          ],
          'pricing_resolve_v482' => {
            'unit_price': 30.5,
            'source': 'Product price',
          },
          'sales_invoice_context_v632' => {'tax_mode': taxMode},
          'sales_additional_charges_enabled_v611' => true,
          'sales_charge_catalog_list_pos_v610' => {'charges': []},
          'client_sale_quote_v630' => {
            'totals': {
              'discount': 0,
              'tax': gst ? 10.98 : 0,
              'taxable': 61,
              'taxable_value': 61,
              'cgst': gst && !interstate ? 5.49 : 0,
              'sgst': gst && !interstate ? 5.49 : 0,
              'igst': gst && interstate ? 10.98 : 0,
              'before_round_off': gst ? 71.98 : 61,
              'automatic_round_off': gst ? .02 : 0,
              'grand_total': gst ? 72 : 61,
            },
            'classified_charge_total': 0,
            'gst': {
              'tax_mode': taxMode,
              'interstate': interstate,
              'lines': [
                {
                  'variant_id': 'msand',
                  'applied_gst_rate': gst ? 18 : 0,
                  'tax_amount': gst ? 10.98 : 0,
                  'taxable_value': 61,
                  'line_total': gst ? 71.98 : 61,
                },
              ],
            },
          },
          'payment_methods_list_v522' => [
            {
              'code': 'cash',
              'display_name': 'Cash',
              'ledger_account_id': 'fixture',
            },
            {'code': 'credit', 'display_name': 'Credit'},
          ],
          _ => throw StateError(
            'Unexpected RPC; this test must not post an invoice: $rpc',
          ),
        };
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    taxMode = 'non_gst';
    interstate = false;
    contextFailure = false;
    calls.clear();
  });

  for (final mode in ThqAppearance.values) {
    for (final gst in [false, true]) {
      for (final layout in [
        (const Size(1366, 900), 1.0),
        (const Size(1024, 768), 1.0),
        (const Size(640, 600), 1.0),
        (const Size(360, 800), 1.5),
        (const Size(320, 480), 2.0),
        (const Size(1280, 650), 1.5),
      ]) {
        testWidgets(
          'all sale fields are reachable, actions stay visible: ${mode.label} GST=$gst $layout',
          (tester) async {
            taxMode = gst ? 'gst_registered' : 'non_gst';
            final (size, scale) = layout;
            final appearance = await showSale(tester, mode, size, scale);
            expect(tester.takeException(), isNull);
            for (final label in [
              'Invoice number',
              'GST status',
              'Customer GSTIN',
              'Due Date',
            ]) {
              expect(find.text(label), findsOneWidget);
              final field = find.byKey(ValueKey('sale-info-$label'));
              expect(field, findsOneWidget);
              await Scrollable.ensureVisible(
                tester.element(field),
                alignment: .25,
              );
              await tester.pumpAndSettle();
              // Read-only labels do not handle pointer events. Their entire
              // rendered field must fit inside the visible invoice viewport.
              expectVisibleBounds(
                tester,
                field,
                find.byKey(const ValueKey('sale-invoice-scroll')),
              );
              expect(find.text('Just Confirm').hitTestable(), findsOneWidget);
              expect(
                find.text('Print & Confirm').hitTestable(),
                findsOneWidget,
              );
            }
            expect(find.text('Auto-generated on confirmation'), findsOneWidget);
            expect(
              find.text(gst ? 'GST registered' : 'Non-GST · No GST charged'),
              findsOneWidget,
            );
            final supply = find.byKey(const ValueKey('sale-place-of-supply'));
            expect(supply, gst ? findsOneWidget : findsNothing);
            if (gst) {
              await tester.ensureVisible(supply);
              await tester.enterText(supply, '32');
              await tester.pumpAndSettle();
            }
            final edit = find.byTooltip('Edit product details');
            await tester.ensureVisible(edit);
            await tester.pumpAndSettle();
            expect(edit.hitTestable(), findsOneWidget);
            expect(
              find.byTooltip('Remove product').hitTestable(),
              findsOneWidget,
            );
            final notes = find.widgetWithText(TextField, 'Notes');
            await tester.ensureVisible(notes);
            await tester.enterText(notes, 'Keep every field');
            final amount = find.widgetWithText(TextField, 'Amount / Tendered');
            await tester.ensureVisible(amount);
            await tester.enterText(amount, '125');
            await tester.pumpAndSettle();
            final before = List<String>.of(calls);
            await appearance.select(
              mode == ThqAppearance.v7
                  ? ThqAppearance.classic
                  : ThqAppearance.v7,
            );
            await tester.pumpAndSettle();
            expect(
              calls,
              before,
              reason: 'Appearance must not make billing requests.',
            );
            expect(find.text('Keep every field'), findsOneWidget);
            expect(find.text('125'), findsOneWidget);
            if (gst) {
              expect(find.text('32'), findsOneWidget);
            }
            expect(find.text('Just Confirm').hitTestable(), findsOneWidget);
            expect(find.text('Print & Confirm').hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
  for (final mode in ThqAppearance.values) {
    testWidgets(
      'interstate invoice shows IGST rather than local components: ${mode.label}',
      (tester) async {
        taxMode = 'gst_registered';
        interstate = true;
        await showSale(tester, mode, const Size(1024, 768), 1);
        expect(find.text('IGST'), findsOneWidget);
        expect(find.text('CGST'), findsNothing);
        expect(find.text('SGST'), findsNothing);
        final taxRow = find
            .ancestor(of: find.text('IGST'), matching: find.byType(Row))
            .first;
        await tester.ensureVisible(taxRow);
        await tester.pumpAndSettle();
        expectVisibleBounds(
          tester,
          taxRow,
          find.byKey(const ValueKey('sale-invoice-scroll')),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      'named credit due date and GST components stay available: ${mode.label}',
      (tester) async {
        taxMode = 'gst_registered';
        await showSale(tester, mode, const Size(1024, 768), 1, named: true);
        // Cash starts fully allocated. Create an actual unpaid balance before
        // expecting a required due date for this named customer.
        final amount = find.widgetWithText(TextField, 'Amount / Tendered');
        await tester.ensureVisible(amount);
        await tester.enterText(amount, '30');
        await tester.pumpAndSettle();
        final due = find.text('Due Date  Required');
        expect(due, findsOneWidget);
        await tester.ensureVisible(due);
        await tester.tap(due);
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.text('CGST'), findsOneWidget);
        expect(find.text('SGST'), findsOneWidget);
        expect(find.text('IGST'), findsNothing);
        final notes = find.widgetWithText(TextField, 'Notes');
        await tester.ensureVisible(notes);
        await tester.enterText(notes, 'Credit order');
        expect(find.text('Just Confirm').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      'invoice setup failure is visible before reaching payment: ${mode.label}',
      (tester) async {
        contextFailure = true;
        await showSale(tester, mode, const Size(640, 600), 1, withItem: false);
        expect(
          find.textContaining(
            'Complete the business GST setup before billing.',
          ),
          findsOneWidget,
        );
        expectVisibleBounds(
          tester,
          find.byKey(const ValueKey('sale-error-banner')),
          find.byType(Scaffold),
        );
        expect(find.text('GST setup not verified'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Revalidating the invoice date must clear the setup message only
        // after the invoice context succeeds.
        contextFailure = false;
        final invoiceDate = find.textContaining('Invoice Date');
        await tester.ensureVisible(invoiceDate);
        await tester.tap(invoiceDate);
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('sale-error-banner')), findsNothing);
        expect(find.text('Non-GST · No GST charged'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
