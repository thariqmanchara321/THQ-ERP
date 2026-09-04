import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  tearDown(ThqNotify.dismissAll);

  testWidgets('routine THQ notification is compact and auto dismisses', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            ThqNotificationHost(child: child ?? const SizedBox.shrink()),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => ThqNotify.success(context, 'Product saved'),
                child: const Text('Save'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.text('Product saved'), findsOneWidget);
    final size = tester.getSize(find.text('Product saved'));
    expect(size.height, lessThan(30));

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Product saved'), findsNothing);
  });

  testWidgets('important notification is not replaced by routine activity', (
    tester,
  ) async {
    late BuildContext hostContext;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            ThqNotificationHost(child: child ?? const SizedBox.shrink()),
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );

    ThqNotify.error(hostContext, 'Payment failed');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    ThqNotify.success(hostContext, 'Product saved');
    await tester.pump();

    expect(find.text('Payment failed'), findsOneWidget);
    expect(find.text('Product saved'), findsNothing);

    // The notification manager intentionally owns a real auto-dismiss timer.
    // Clear it before the widget-test invariant check so no timer survives the
    // test body.
    ThqNotify.dismissAll();
    await tester.pump();
  });
}
