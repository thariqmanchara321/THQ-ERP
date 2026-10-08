import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  for (final singleLine in [false, true]) {
    for (final showClock in [false, true]) {
      testWidgets('version clock layout $singleLine / clock $showClock', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ThqVersionClock(
                version: '7.0.1',
                buildNumber: 15,
                singleLine: singleLine,
                showClock: showClock,
              ),
            ),
          ),
        );
        final text = tester.widget<Text>(find.byType(Text)).data!;
        expect(text, contains('v7.0.1'));
        expect(text, contains('Build 15'));
        expect(text.contains('\n'), !singleLine);
        expect(RegExp(r'\d{2}:\d{2}').hasMatch(text), showClock);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 31));
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
