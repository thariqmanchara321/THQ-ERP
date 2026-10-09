import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  testWidgets('ThqBusinessLogo renders fallback when logoUrl is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ThqBusinessLogo(
            logoUrl: '',
            size: 40,
            fallback: Text('FALLBACK_TEXT'),
          ),
        ),
      ),
    );

    expect(find.text('FALLBACK_TEXT'), findsOneWidget);
  });

  testWidgets('ThqBusinessLogo renders fallback when logoUrl is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ThqBusinessLogo(
            logoUrl: null,
            size: 40,
            fallback: Icon(Icons.star),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('ThqBusinessLogo decodes base64 data URI', (tester) async {
    // 1x1 transparent PNG bytes in base64
    const transparentPng =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ThqBusinessLogo(
            logoUrl: transparentPng,
            size: 40,
            fallback: Text('FAIL'),
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('FAIL'), findsNothing);
  });
}
