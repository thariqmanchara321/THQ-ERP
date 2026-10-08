import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client_app/widgets/tracking_conversion_dialog.dart';

void main() {
  testWidgets('tracking conversion cannot confirm unresolved stock blockers', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TrackingConversionDialog(
      productName: 'Aggregate', mode: 'none', preview: const {
        'mode': 'batch', 'locations': [], 'history': [],
        'blockers': ['Finish the outstanding transfer.'],
      },
    ))));
    expect(find.text('Finish the outstanding transfer.'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm Conversion'));
    expect(button.onPressed, isNull);
  });

  testWidgets('ready conversion still requires a reason and device sync confirmation', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TrackingConversionDialog(
      productName: 'Aggregate', mode: 'none', preview: const {
        'mode': 'batch', 'locations': [], 'history': [], 'blockers': [],
      },
    ))));
    await tester.tap(find.text('Confirm Conversion'));
    await tester.pump();
    expect(find.text('Confirm that all devices have synced.'), findsOneWidget);
  });
}
