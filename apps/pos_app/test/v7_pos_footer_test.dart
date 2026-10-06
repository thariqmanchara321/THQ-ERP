import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/client_session.dart';
import 'package:pos_app/screens/pos_home_screen.dart';
import 'package:thq_ui/thq_ui.dart';

const session = ClientSession(
  business: ClientBusiness(
    id: 'fixture',
    membershipId: 'fixture',
    name: 'THQ POS',
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

Future<void> open(WidgetTester tester, {double scale = 1}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => ThqMotionSettings.enabled.value = true);
  addTearDown(ThqNotify.dismissAll);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThqV7Theme.desktop(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: ThqNotificationHost(child: ThqMotionScope(child: child!)),
      ),
      // No activated device: settings load locally without any network calls.
      home: const PosHomeScreen(session: session),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('footer is compact and collapsing preserves the workspace', (
    tester,
  ) async {
    await open(tester);
    final footer = find.byKey(const ValueKey('pos-sidebar-footer'));
    expect(tester.getSize(footer).height, lessThanOrEqualTo(64));
    expect(
      find.descendant(of: footer, matching: find.text('Sign Out')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: footer, matching: find.text('Collapse')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: footer, matching: find.byType(ThqVersionClock)),
      findsNothing,
    );
    expect(
      find.descendant(of: footer, matching: find.byIcon(Icons.refresh)),
      findsNothing,
    );
    expect(find.text('v7.0.0 · Build 14'), findsOneWidget);
    final workspace = find.text('POS device is not activated.');
    expect(workspace, findsOneWidget);
    await tester.tap(find.text('Collapse'));
    await tester.pumpAndSettle();
    expect(workspace, findsOneWidget);
    expect(find.text('v7'), findsOneWidget);
    await tester.tap(find.byTooltip('Expand'));
    await tester.pumpAndSettle();
    expect(find.text('Collapse'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('terminal menu retains safe refresh and reduced motion', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Terminal actions'));
    await tester.pumpAndSettle();
    expect(find.text('Cashier · owner'), findsOneWidget);
    await tester.tap(find.text('Reduce motion'));
    await tester.pumpAndSettle();
    expect(ThqMotionSettings.enabled.value, isFalse);
    await tester.tap(find.byTooltip('Terminal actions'));
    await tester.pumpAndSettle();
    expect(find.text('Enable motion'), findsOneWidget);
    await tester.tap(find.text('Refresh POS'));
    await tester.pumpAndSettle();
    // An inactive Settings fixture exercises the existing refresh error path.
    // The Billing cart confirmation handler is preserved by the source audit.
    expect(
      find.textContaining('Refresh failed:', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('POS device is not activated.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    ThqNotify.dismissAll();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('footer remains usable with larger text', (tester) async {
    await open(tester, scale: 1.5);
    expect(
      tester.getSize(find.byKey(const ValueKey('pos-sidebar-footer'))).height,
      lessThanOrEqualTo(100),
    );
    expect(find.text('Sign Out').hitTestable(), findsOneWidget);
    expect(find.text('Collapse').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
