import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

class MemoryAppearanceStore implements ThqAppearanceStore {
  final values = <String, String>{};
  final writes = <String>[];
  Completer<String?>? readGate;
  Completer<void>? writeGate;
  bool failRead = false;
  bool failWrite = false;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('read unavailable');
    return readGate == null ? values[key] : readGate!.future;
  }

  @override
  Future<void> write(String key, String value) async {
    writes.add(value);
    if (writeGate != null) await writeGate!.future;
    if (failWrite) throw StateError('write unavailable');
    values[key] = value;
  }
}

void main() {
  test(
    'unknown preference uses V7 and a saved Classic choice restores',
    () async {
      final store = MemoryAppearanceStore();
      final controller = ThqAppearanceController(
        appKey: 'client',
        store: store,
      );
      store.values[controller.storageKey] = 'future-unknown-mode';
      await controller.load();
      expect(controller.value, ThqAppearance.v7);
      expect(await controller.select(ThqAppearance.classic), isTrue);
      final restarted = ThqAppearanceController(appKey: 'client', store: store);
      await restarted.load();
      expect(restarted.value, ThqAppearance.classic);
      controller.dispose();
      restarted.dispose();
    },
  );

  test(
    'all five apps have independent preferences and preserve other keys',
    () async {
      final store = MemoryAppearanceStore()
        ..values['auth-session-fixture'] = 'unchanged';
      for (final app in [
        'client',
        'pos',
        'admin',
        'client_mobile',
        'mobile_pos',
      ]) {
        final controller = ThqAppearanceController(appKey: app, store: store);
        await controller.load();
        expect(controller.value, ThqAppearance.v7);
        await controller.select(ThqAppearance.classic);
        controller.dispose();
      }
      expect(store.values.length, 6);
      expect(store.values['auth-session-fixture'], 'unchanged');
    },
  );

  test(
    'preference failures do not block startup or switching and allow retry',
    () async {
      final store = MemoryAppearanceStore()..failRead = true;
      final controller = ThqAppearanceController(
        appKey: 'client',
        store: store,
      );
      await controller.load();
      expect(controller.loaded, isTrue);
      expect(controller.value, ThqAppearance.v7);
      store.failWrite = true;
      expect(await controller.select(ThqAppearance.classic), isFalse);
      expect(controller.value, ThqAppearance.classic);
      expect(controller.saveFailed, isTrue);
      store.failWrite = false;
      expect(await controller.select(ThqAppearance.classic), isTrue);
      expect(controller.saveFailed, isFalse);
      expect(store.values[controller.storageKey], 'classic');
      controller.dispose();
    },
  );

  test('queued writes keep the last choice on disk', () async {
    final store = MemoryAppearanceStore()..writeGate = Completer<void>();
    final controller = ThqAppearanceController(appKey: 'pos', store: store);
    await controller.load();
    final first = controller.select(ThqAppearance.classic);
    await Future<void>.delayed(Duration.zero);
    final second = controller.select(ThqAppearance.v7);
    expect(store.writes, ['classic']);
    expect(controller.value, ThqAppearance.v7);
    store.writeGate!.complete();
    expect(await Future.wait([first, second]), [true, true]);
    expect(store.writes, ['classic', 'v7']);
    expect(store.values[controller.storageKey], 'v7');
    expect(controller.saving, isFalse);
    controller.dispose();
  });

  test(
    'a late load never overrides a click or notifies a disposed controller',
    () async {
      final store = MemoryAppearanceStore()..readGate = Completer<String?>();
      final controller = ThqAppearanceController(
        appKey: 'client',
        store: store,
      );
      final loading = controller.load();
      await controller.select(ThqAppearance.classic);
      store.readGate!.complete('v7');
      await loading;
      expect(controller.value, ThqAppearance.classic);
      controller.dispose();
      final pendingStore = MemoryAppearanceStore()
        ..readGate = Completer<String?>();
      final disposed = ThqAppearanceController(
        appKey: 'pos',
        store: pendingStore,
      );
      final pending = disposed.load();
      disposed.dispose();
      pendingStore.readGate!.complete('classic');
      await pending;
    },
  );

  test(
    'Classic restores legacy palettes and V7 retains the source profile',
    () {
      for (final app in ['client', 'pos', 'admin']) {
        final v7 = UiDesignProfile.fallback(app);
        final classic = v7.forAppearance(ThqAppearance.classic);
        expect(classic.primary, const Color(0xFF6C5CE7));
        expect(classic.surface, Colors.white);
        expect(classic.theme().brightness, Brightness.light);
        expect(v7.theme().brightness, Brightness.dark);
        expect(identical(classic.forAppearance(ThqAppearance.v7), v7), isTrue);
      }
      expect(
        ThqMobileTheme.client(
          appearance: ThqAppearance.classic,
        ).colorScheme.primary,
        const Color(0xFF635BFF),
      );
      expect(
        ThqMobileTheme.pos(
          appearance: ThqAppearance.classic,
        ).colorScheme.primary,
        const Color(0xFF1769E0),
      );
    },
  );

  test(
    'standard and custom tenant presets keep their independent colour choices',
    () {
      final raw = {'primary': '#AA4455', 'pos_cart_width': 400};
      final custom = UiDesignProfile.fromMap({
        'key': 'custom',
        'config': raw,
      }, 'pos');
      final classic = custom.forAppearance(ThqAppearance.classic);
      expect(custom.primary, const Color(0xFFAA4455));
      expect(classic.primary, custom.primary);
      expect(classic.posCartWidth, 400);
      expect(raw, {'primary': '#AA4455', 'pos_cart_width': 400});
      final standard = UiDesignProfile.fromMap({
        'key': 'client_aurora',
        'config': UiDesignProfile.classicDefaultConfig('client'),
        'overrides': {'primary': '#AA4455'},
      }, 'client');
      expect(standard.primary, const Color(0xFFAA4455));
      expect(
        standard.forAppearance(ThqAppearance.classic).primary,
        standard.primary,
      );
      final upgraded = UiDesignProfile.fromMap({
        'key': 'client_aurora',
        'config': UiDesignProfile.defaultConfig,
      }, 'client');
      expect(
        upgraded.forAppearance(ThqAppearance.classic).primary,
        const Color(0xFF6C5CE7),
      );
    },
  );

  testWidgets(
    'header switching preserves cart, draft, focus and Navigator routes',
    (tester) async {
      final store = MemoryAppearanceStore();
      final controller = ThqAppearanceController(
        appKey: 'client',
        store: store,
      );
      await controller.load();
      var mounts = 0;
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ThqAppearanceHost(
          appKey: 'client',
          controller: controller,
          builder: (context, mode) => MaterialApp(
            navigatorKey: navigatorKey,
            themeAnimationDuration: Duration.zero,
            theme: UiDesignProfile.fallback(
              'client',
            ).forAppearance(mode).theme(),
            home: DraftWorkspace(onMount: () => mounts++),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final navigator = navigatorKey.currentState;
      await tester.tap(find.text('Add M-sand'));
      await tester.tap(find.text('Add M-sand'));
      await tester.enterText(
        find.byKey(const ValueKey('draft-note')),
        'Truck KL-01 / yard delivery',
      );
      await tester.enterText(
        find.byKey(const ValueKey('draft-payment')),
        '125.50',
      );
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('draft-payment')),
          matching: find.byType(EditableText),
        ),
      );
      final focus = editable.focusNode;
      await controller.select(ThqAppearance.classic);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(find.text('M-sand: 2 foot'), findsOneWidget);
      expect(find.text('125.50'), findsOneWidget);
      expect(find.text('Truck KL-01 / yard delivery'), findsOneWidget);
      expect(mounts, 1);
      expect(navigatorKey.currentState, same(navigator));
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('draft-note'))),
        ).brightness,
        Brightness.light,
      );
      await tester.tap(find.byType(ThqAppearanceButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('V7 UI'));
      await tester.pumpAndSettle();
      expect(store.values[controller.storageKey], 'v7');
      expect(find.text('M-sand: 2 foot'), findsOneWidget);
      expect(mounts, 1);

      await tester.tap(find.text('Review payment'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('payment-reference')),
        'UPI-123',
      );
      await controller.select(ThqAppearance.classic);
      await tester.pumpAndSettle();
      expect(find.text('Payment review'), findsOneWidget);
      expect(find.text('UPI-123'), findsOneWidget);
      expect(navigatorKey.currentState, same(navigator));
      await tester.tap(find.text('Close review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open details'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('detail-note')),
        'Do not reset this route',
      );
      await controller.select(ThqAppearance.v7);
      await tester.pumpAndSettle();
      expect(find.text('Do not reset this route'), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isTrue);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('M-sand: 2 foot'), findsOneWidget);
      expect(find.text('125.50'), findsOneWidget);
      expect(mounts, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('invoice paper stays light in both appearances', (tester) async {
    final controller = ThqAppearanceController(
      appKey: 'client',
      store: MemoryAppearanceStore(),
    );
    await tester.pumpWidget(
      ThqAppearanceHost(
        appKey: 'client',
        controller: controller,
        builder: (context, mode) => MaterialApp(
          theme: UiDesignProfile.fallback('client').forAppearance(mode).theme(),
          home: const ThqInvoicePaperScope(child: Text('Invoice paper')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final mode in ThqAppearance.values) {
      await controller.select(mode);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Invoice paper'))).brightness,
        Brightness.light,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

class DraftWorkspace extends StatefulWidget {
  const DraftWorkspace({super.key, required this.onMount});
  final VoidCallback onMount;
  @override
  State<DraftWorkspace> createState() => _DraftWorkspaceState();
}

class _DraftWorkspaceState extends State<DraftWorkspace> {
  final note = TextEditingController();
  final payment = TextEditingController();
  int quantity = 0;
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    note.dispose();
    payment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Sale draft'),
      actions: const [ThqAppearanceButton()],
    ),
    body: Column(
      children: [
        Text('M-sand: $quantity foot'),
        FilledButton(
          onPressed: () => setState(() => quantity++),
          child: const Text('Add M-sand'),
        ),
        TextField(key: const ValueKey('draft-note'), controller: note),
        TextField(key: const ValueKey('draft-payment'), controller: payment),
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Payment review'),
              content: const TextField(key: ValueKey('payment-reference')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close review'),
                ),
              ],
            ),
          ),
          child: const Text('Review payment'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: TextField(key: ValueKey('detail-note'))),
            ),
          ),
          child: const Text('Open details'),
        ),
      ],
    ),
  );
}
