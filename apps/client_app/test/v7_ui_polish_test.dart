import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:client_app/models/client_session.dart';
import 'package:client_app/models/report_document.dart';
import 'package:client_app/screens/client_home_screen.dart';
import 'package:client_app/screens/reports_center_v500_screen.dart';
import 'package:client_app/screens/sales_screen.dart';
import 'package:client_app/services/location_scope_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Uses the existing Supabase transport for local, read-only fixtures.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thq_ui/thq_ui.dart';

import 'reports_center_v5_test.dart' show FakeReports, fixture;

const _session = ClientSession(
  business: ClientBusiness(
    id: 'fixture',
    membershipId: 'fixture',
    name: 'THQ Traders',
    slug: 'fixture',
    businessType: 'retail',
    status: 'active',
  ),
  modules: [
    ClientModule(
      key: 'sales_details',
      name: 'Sales Details',
      description: null,
      category: 'Sales',
      sortOrder: 1,
    ),
  ],
  roles: {'owner'},
  permissions: {},
  currencyCode: 'INR',
  timezone: 'Asia/Kolkata',
  locale: 'en_IN',
  canViewAllLocations: true,
);

class _Store implements ThqAppearanceStore {
  _Store(this.mode);
  String mode;
  @override
  Future<String?> read(String key) async => mode;
  @override
  Future<void> write(String key, String value) async => mode = value;
}

Map<String, dynamic> _registerFixture() {
  final data = fixture();
  final columns = [
    for (final (key, label, type, width) in [
      ('sale_number', 'Invoice Number', 'text', 180),
      ('sale_date', 'Date', 'date', 130),
      ('customer_name', 'Customer', 'text', 200),
      ('location_name', 'Store / Warehouse', 'text', 180),
      ('taxable_total', 'Taxable Amount', 'money', 170),
      ('tax_total', 'Tax Amount', 'money', 150),
      ('grand_total', 'Invoice Total', 'money', 180),
      ('paid_as_of', 'Paid to As-of', 'money', 160),
      ('outstanding', 'Outstanding', 'money', 170),
      ('status', 'Status', 'text', 130),
    ])
      {'key': key, 'label': label, 'type': type, 'width': width},
  ];
  data['definition'] = {
    ...reportMap(data['definition']),
    'title': 'Sales Register',
    'columns': columns,
  };
  data['columns'] = columns;
  data['rows'] = [
    {
      ...reportMaps(data['rows']).first,
      'sale_date': '2026-10-06',
      'customer_name': 'Walk-in Customer',
      'location_name': 'Main Store',
      'taxable_total': 8875.0,
      'tax_total': 0.0,
      'grand_total': 8875.0,
      'paid_as_of': 8875.0,
      'outstanding': 0.0,
      'status': 'posted',
    },
  ];
  data['summary'] = [
    {'key': 'invoice_count', 'label': 'Invoices', 'value': 1, 'type': 'number'},
    for (final (key, label) in [
      ('taxable_total', 'Taxable Amount'),
      ('tax_total', 'Tax Amount'),
      ('grand_total', 'Invoice Total'),
      ('paid_as_of', 'Paid to As-of'),
      ('outstanding', 'Outstanding'),
    ])
      {
        'key': key,
        'label': label,
        'value': reportMaps(data['rows']).first[key],
        'type': 'money',
      },
  ];
  return data;
}

class _Register extends FakeReports {
  @override
  Future<List<ReportDefinition>> catalog(String tenantId) async => [
    ReportDefinition.fromMap(reportMap(_registerFixture()['definition'])),
  ];
  @override
  Future<ReportDocument> run(ReportRequest request) async {
    requests.add(request);
    return ReportDocument.fromMap(_registerFixture());
  }
}

Future<ThqAppearanceController> _open(
  WidgetTester tester,
  Widget child,
  ThqAppearance mode,
  Size size, {
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final appearance = ThqAppearanceController(
    appKey: 'client',
    store: _Store(mode.name),
  );
  await appearance.load();
  addTearDown(appearance.dispose);
  await tester.pumpWidget(
    ThqAppearanceHost(
      appKey: 'client',
      controller: appearance,
      builder: (_, mode) => MaterialApp(
        themeAnimationDuration: Duration.zero,
        theme: UiDesignProfile.fallback('client')
            .forAppearance(mode)
            .theme()
            .copyWith(
              textTheme: UiDesignProfile.fallback('client')
                  .forAppearance(mode)
                  .theme()
                  .textTheme
                  .apply(fontFamily: 'Roboto'),
            ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: const ValueKey('preview'), child: child!),
        ),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return appearance;
}

Future<void> _preview(WidgetTester tester, String name) async {
  final directory = Platform.environment['THQ_UI_PREVIEW_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

var _salesReads = 0;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Check widths using real glyph metrics rather than the square test font.
    final fonts = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/report_fonts/ReportSans.ttf'))
      ..addFont(rootBundle.load('assets/report_fonts/ReportSans-Bold.ttf'));
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : true,
        );
    await Supabase.initialize(
      url: 'https://thq-ui-polish.invalid',
      publishableKey: 'sb_publishable_fixture',
      authOptions: const FlutterAuthClientOptions(persistSession: false),
      accessToken: () async => null,
      httpClient: MockClient((request) async {
        final rpc = request.url.path.split('/').last;
        final Object? result;
        switch (rpc) {
          case 'sales_list_v32':
            _salesReads++;
            result = [
              for (final status in ['paid', 'partial', 'unpaid'])
                {
                  'sale_id': status,
                  'invoice_number': 'INV-$status',
                  'sale_date': '2026-10-06',
                  'customer_name': 'Customer $status',
                  'grand_total': 100,
                  'paid_amount': status == 'paid' ? 100 : 20,
                  'balance_due': status == 'paid' ? 0 : 80,
                  'payment_status': status,
                  'status': 'posted',
                },
            ];
          case 'tenant_ui_design_get_v43':
            result = null;
          case 'app_menu_tree_v45':
            result = [];
          default:
            throw StateError('Unexpected read-only UI fixture RPC: $rpc');
        }
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
  setUp(() => LocationScopeService.selectedLocationId.value = null);

  for (final mode in ThqAppearance.values) {
    testWidgets('payment words contrast with every badge in ${mode.label}', (
      tester,
    ) async {
      await _open(
        tester,
        const SalesScreen(session: _session, historyOnly: true),
        mode,
        const Size(1060, 768),
      );
      for (final label in ['PAID', 'PARTIAL', 'UNPAID']) {
        final text = find.text(label);
        expect(text, findsOneWidget);
        final background = tester
            .widgetList<Container>(
              find.ancestor(of: text, matching: find.byType(Container)),
            )
            .map((w) => w.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.color != null)
            .color!;
        final foreground = tester.widget<Text>(text).style!.color!;
        final a = background.computeLuminance(),
            b = foreground.computeLuminance();
        expect(
          ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'clock stays below workspace when sidebar collapses in ${mode.label}',
      (tester) async {
        final appearance = await _open(
          tester,
          const ClientHomeScreen(session: _session),
          mode,
          const Size(1366, 768),
        );
        final clock = find.byType(ThqVersionClock);
        expect(clock, findsOneWidget);
        expect(tester.widget<ThqVersionClock>(clock).singleLine, isTrue);
        final before = tester.getRect(clock);
        final signOut = tester.getRect(find.text('Sign Out'));
        expect(before.left, greaterThan(signOut.right));
        expect(before.height, lessThan(24));
        expect(before.bottom, lessThanOrEqualTo(768));
        final reads = _salesReads;
        await tester.tap(find.text('Collapse'));
        await tester.pumpAndSettle();
        expect(tester.getRect(clock).right, closeTo(before.right, 1));
        await appearance.select(
          mode == ThqAppearance.v7 ? ThqAppearance.classic : ThqAppearance.v7,
        );
        await tester.pumpAndSettle();
        expect(_salesReads, reads);
        expect(find.text('PAID'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'all ten columns and six totals fit compact desktop reports in ${mode.label}',
      (tester) async {
        final service = _Register();
        await _open(
          tester,
          ReportsCenterV500Screen(session: _session, service: service),
          mode,
          const Size(1060, 768),
        );
        final scroll = tester.widget<SingleChildScrollView>(
          find.byKey(const ValueKey('report-horizontal-scroll')),
        );
        expect(
          scroll.controller!.position.maxScrollExtent,
          lessThanOrEqualTo(1),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('report-toolbar'))).height,
          lessThan(130),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('report-summary'))).height,
          lessThan(100),
        );
        for (final column in ReportDocument.fromMap(
          _registerFixture(),
        ).columns) {
          expect(find.text(column.label), findsWidgets);
        }
        final lastTotal = find.descendant(
          of: find.byKey(const ValueKey('report-summary')),
          matching: find.text('Outstanding'),
        );
        expect(tester.getRect(lastTotal).right, lessThan(1060));
        final status = find.text('Posted');
        expect(tester.getRect(status).right, lessThanOrEqualTo(1060));
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.descendant(
            of: find.byKey(const ValueKey('report-summary')),
            matching: find.byType(Text),
          ),
        )) {
          expect(paragraph.didExceedMaxLines, isFalse);
        }
        await _preview(tester, 'reports-${mode.name}');
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('report-horizontal-scroll')),
            matching: find.text('Invoice Total'),
          ),
        );
        await tester.pumpAndSettle();
        expect(service.requests.last.sortKey, 'grand_total');
        await tester.tap(find.text('INV-1'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Saved evidence'));
        await tester.tap(find.text('Saved evidence'));
        await tester.pumpAndSettle();
        expect(find.text('Saved Driver'), findsOneWidget);
        expect(find.text('LAST_FIELD'), findsOneWidget);
        expect(service.requests, hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'large negative report amounts stay complete in ${mode.label}',
      (tester) async {
        final data = _registerFixture();
        (data['rows'] as List).first['grand_total'] = -1234567890.12;
        final document = ReportDocument.fromMap(data);
        final service = FakeReports()..handler = (_) async => document;
        await _open(
          tester,
          ReportsCenterV500Screen(session: _session, service: service),
          mode,
          const Size(640, 480),
          scale: 1.5,
        );
        final amount = find.text(document.format(-1234567890.12, 'money'));
        expect(amount, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(amount).didExceedMaxLines,
          isFalse,
        );
        final scroll = tester.widget<SingleChildScrollView>(
          find.byKey(const ValueKey('report-horizontal-scroll')),
        );
        expect(scroll.controller!.position.maxScrollExtent, greaterThan(0));
        expect(tester.takeException(), isNull);
      },
    );

    for (final (size, scale) in [
      (const Size(320, 700), 1.5),
      (const Size(1366, 360), 1.7),
    ]) {
      testWidgets(
        'report filters and totals remain reachable in ${mode.label} / $size / $scale',
        (tester) async {
          final service = _Register();
          await _open(
            tester,
            ReportsCenterV500Screen(session: _session, service: service),
            mode,
            size,
            scale: scale,
          );
          await tester.tap(find.byTooltip('Report totals and basis'));
          await tester.pumpAndSettle();
          expect(find.text('Outstanding'), findsWidgets);
          expect(
            find.text(
              'Saved invoices, payments and all driver and load evidence.',
            ),
            findsOneWidget,
          );
          await tester.ensureVisible(find.text('Close'));
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Dates, store and search'));
          await tester.pumpAndSettle();
          expect(find.text('Search all saved fields'), findsOneWidget);
          expect(find.textContaining('From '), findsOneWidget);
          expect(find.textContaining('To '), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
