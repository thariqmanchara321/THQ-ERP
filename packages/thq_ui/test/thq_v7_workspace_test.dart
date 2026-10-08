import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  tearDown(() => ThqMotionSettings.enabled.value = true);

  testWidgets('invoice paper text remains readable inside the navy app', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThqV7Theme.desktop(),
        home: const Scaffold(
          body: ThqInvoicePaperScope(
            child: ColoredBox(
              color: Colors.white,
              child: Text('GST invoice · Total 1,180.00'),
            ),
          ),
        ),
      ),
    );
    final ink = tester.widget<RichText>(find.byType(RichText));
    final foreground = ink.text.style!.color!;
    final contrast = 1.05 / (foreground.computeLuminance() + .05);
    expect(contrast, greaterThan(4.5));
    expect(find.text('GST invoice · Total 1,180.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'selected product header fits a small tile at text scale $scale',
      (tester) async {
        var favorites = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThqV7Theme.mobile(),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SizedBox(
                  width: 128,
                  child: ThqProductSelectionHeader(
                    icon: Icons.inventory_2_outlined,
                    quantity: '120.50',
                    quantityDescription: 'In cart: 120.50 CFT',
                    tracking: 'BATCH',
                    favorite: false,
                    onFavorite: () => favorites++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('In cart: 120.50 CFT'), findsOneWidget);
        expect(
          tester.getSize(find.byType(IconButton)).width,
          greaterThanOrEqualTo(48),
        );
        await tester.tap(find.byTooltip('Add favorite'));
        await tester.pumpAndSettle();
        expect(favorites, 1);
      },
    );
  }

  test(
    'V7 upgrades the standard palette while preserving tenant overrides',
    () {
      final profile = UiDesignProfile.fromMap({
        'key': 'client_aurora',
        'config': {'primary': '#AAAAAA', 'pos_cart_width': 455},
        'overrides': {'primary': '#FFCC33', 'pos_cart_width': 320},
      }, 'client');
      expect(profile.background, ThqPalette.background);
      expect(profile.primary, const Color(0xFFFFCC33));
      expect(profile.posCartWidth, 320);
      final custom = UiDesignProfile.fromMap({
        'key': 'tenant_custom',
        'config': {'background': '#F4F4F4', 'primary': '#336699'},
      }, 'client');
      expect(custom.background, const Color(0xFFF4F4F4));
      expect(custom.primary, const Color(0xFF336699));
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'dialog preserves result and focus with reduced motion $reduced',
      (tester) async {
        int? result;
        ModalRoute<dynamic>? route;
        final focus = FocusNode();
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThqV7Theme.desktop(),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Builder(
                builder: (context) => Scaffold(
                  body: FilledButton(
                    focusNode: focus,
                    onPressed: () async {
                      result = await showThqDialog<int>(
                        context: context,
                        builder: (dialogContext) {
                          route = ModalRoute.of(dialogContext);
                          return AlertDialog(
                            title: const Text('Confirm'),
                            content: const TextField(autofocus: true),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, 7),
                                child: const Text('Save'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        focus.requestFocus();
        await tester.pump();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          route!.transitionDuration,
          reduced ? Duration.zero : const Duration(milliseconds: 300),
        );
        await tester.enterText(find.byType(TextField), 'retained');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(result, 7);
        expect(focus.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('editing invoice quantity retains customer input and focus', (
    tester,
  ) async {
    final customer = TextEditingController(text: 'Customer 1');
    final focus = FocusNode();
    addTearDown(customer.dispose);
    addTearDown(focus.dispose);
    late StateSetter update;
    var quantity = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThqV7Theme.desktop(),
        home: Scaffold(
          body: ThqMotionScope(
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return ThqPageEntrance(
                  child: Column(
                    children: [
                      TextField(controller: customer, focusNode: focus),
                      Text('Quantity $quantity'),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Customer 1 · retained');
    update(() => quantity++);
    await tester.pump();
    expect(customer.text, 'Customer 1 · retained');
    expect(focus.hasFocus, isTrue);
    expect(find.text('Quantity 2'), findsOneWidget);
  });

  testWidgets('motion toggle honors the system preference', (tester) async {
    late BuildContext inside;
    Widget app(bool systemReduced) => MaterialApp(
      theme: ThqV7Theme.desktop(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: systemReduced),
        child: ThqMotionScope(
          child: Builder(
            builder: (context) {
              inside = context;
              return const Scaffold(body: ThqMotionButton());
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(false));
    expect(MediaQuery.disableAnimationsOf(inside), isFalse);
    await tester.tap(find.byTooltip('Reduce motion'));
    await tester.pump();
    expect(MediaQuery.disableAnimationsOf(inside), isTrue);
    await tester.pumpWidget(app(true));
    await tester.tap(find.byTooltip('Enable motion'));
    await tester.pump();
    expect(MediaQuery.disableAnimationsOf(inside), isTrue);
  });

  testWidgets('six important table columns fit without horizontal scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThqV7Theme.desktop(),
        home: Scaffold(
          body: SizedBox(
            width: 720,
            height: 400,
            child: ThqDenseTable(
              columns: const [
                ThqTableColumn(label: 'Product', width: 220),
                ThqTableColumn(label: 'SKU'),
                ThqTableColumn(label: 'Store'),
                ThqTableColumn(label: 'Unit'),
                ThqTableColumn(
                  label: 'Stock',
                  alignment: Alignment.centerRight,
                ),
                ThqTableColumn(
                  label: 'Value',
                  alignment: Alignment.centerRight,
                ),
              ],
              rows: const [
                ThqTableRow(
                  cells: [
                    Text('Aggregate'),
                    Text('AG-01'),
                    Text('Main'),
                    Text('TON'),
                    Text('120.50'),
                    Text('24,100.00'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final horizontal = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .where((s) => axisDirectionToAxis(s.axisDirection) == Axis.horizontal);
    expect(horizontal, hasLength(1));
    expect(horizontal.single.position.maxScrollExtent, closeTo(0, .01));
    expect(find.text('120.50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(400, 800), const Size(1280, 800)]) {
    testWidgets('transaction sections remain available at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThqV7Theme.desktop(),
          home: Scaffold(
            body: ThqTransactionWorkspace(
              header: const Text('New Sale'),
              details: const TextField(
                decoration: InputDecoration(labelText: 'Customer'),
              ),
              items: const SizedBox(height: 200, child: Text('Invoice lines')),
              payment: FilledButton(
                onPressed: () {},
                child: const Text('Confirm invoice'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Customer'), findsOneWidget);
      expect(find.text('Confirm invoice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'large text and open keyboard do not truncate the transaction page',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThqV7Theme.mobile(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
              textScaler: TextScaler.linear(2),
              viewInsets: EdgeInsets.only(bottom: 300),
            ),
            child: Scaffold(
              body: ThqTransactionWorkspace(
                header: const Text('New Sale'),
                details: const TextField(
                  decoration: InputDecoration(labelText: 'Customer'),
                ),
                items: const SizedBox(
                  height: 200,
                  child: Text('Invoice lines'),
                ),
                payment: FilledButton(
                  onPressed: () {},
                  child: const Text('Confirm invoice'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirm invoice'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  test('palette supports readable text on the primary payment action', () {
    final s = ThqV7Theme.desktop().colorScheme;
    final a = s.primary.computeLuminance(), b = s.onPrimary.computeLuminance();
    final contrast = (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05));
    expect(contrast, greaterThan(4.5));
  });
}
