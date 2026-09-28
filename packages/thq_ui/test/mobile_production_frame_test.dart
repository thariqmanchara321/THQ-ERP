import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  testWidgets('production frame keeps text scaling within 200 percent', (
    tester,
  ) async {
    double? observedScale;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThqMobileTheme.client(),
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: const TextScaler.linear(3.0)),
            child: ThqMobileProductionFrame(
              child: Builder(
                builder: (context) {
                  observedScale = MediaQuery.of(context).textScaler.scale(1.0);
                  return child ?? const SizedBox.shrink();
                },
              ),
            ),
          );
        },
        home: const Scaffold(body: Text('Ready')),
      ),
    );

    expect(observedScale, 2.0);
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('release banner stays compact and shows the latest version', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThqMobileTheme.pos(),
        home: const Scaffold(
          body: ThqMobileReleaseBanner(
            currentVersion: '6.2.3',
            latestVersion: '6.2.4',
            notes: 'Production polish',
          ),
        ),
      ),
    );

    expect(find.text('Update available: v6.2.4'), findsOneWidget);
    expect(find.text('Production polish'), findsOneWidget);
  });
}
