import 'package:admin_panel/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows THQ Super Admin login', (tester) async {
    await tester.pumpWidget(const ThqAdminApp(authenticatedOverride: false));

    expect(find.text('THQ'), findsOneWidget);
    expect(find.text('Super Admin'), findsOneWidget);

    expect(find.byType(TextField), findsNWidgets(2));

    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Platform administration only'), findsOneWidget);
  });
}
