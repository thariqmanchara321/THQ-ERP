import 'package:admin_panel/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  testWidgets(
    'Admin restores Classic and switching preserves login fields and route',
    (tester) async {
      final store = AdminAppearanceStore();
      final controller = ThqAppearanceController(appKey: 'admin', store: store);
      await controller.load();
      await tester.pumpWidget(
        ThqAdminApp(authenticatedOverride: false, appearance: controller),
      );
      await tester.pump(const Duration(milliseconds: 3600));
      await tester.pumpAndSettle();
      final username = find.widgetWithText(TextField, 'Username');
      final password = find.widgetWithText(TextField, 'Password');
      await tester.enterText(username, 'fixture-admin');
      await tester.enterText(password, 'fixture-password');
      expect(Theme.of(tester.element(username)).brightness, Brightness.light);
      final fieldState = tester.state(username);
      await tester.tap(find.byType(ThqAppearanceButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('V7 UI'));
      await tester.pumpAndSettle();
      expect(tester.state(username), same(fieldState));
      expect(find.text('fixture-admin'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: password,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'fixture-password',
      );
      expect(Theme.of(tester.element(username)).brightness, Brightness.dark);
      expect(store.value, 'v7');
      expect(find.text('Sign In').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
  testWidgets('shows THQ Super Admin login', (tester) async {
    await tester.pumpWidget(const ThqAdminApp(authenticatedOverride: false));
    await tester.pump(const Duration(milliseconds: 3600));
    await tester.pumpAndSettle();

    expect(find.text('THQ'), findsOneWidget);
    expect(find.text('Super Admin'), findsOneWidget);

    expect(find.byType(TextField), findsNWidgets(2));

    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Platform administration only'), findsOneWidget);
  });
}

class AdminAppearanceStore implements ThqAppearanceStore {
  String value = 'classic';
  @override
  Future<String?> read(String key) async => value;
  @override
  Future<void> write(String key, String next) async {
    value = next;
  }
}
