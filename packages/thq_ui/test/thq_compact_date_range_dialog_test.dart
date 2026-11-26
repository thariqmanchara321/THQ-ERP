import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  group('ThqCompactDateRangeDialog Tests', () {
    testWidgets('renders dialog with title, presets, month navigation and calendar', (tester) async {
      DateTimeRange? result;
      final initial = DateTimeRange(
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 15),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showThqCompactDateRangePicker(
                    context: context,
                    initialRange: initial,
                    title: 'Select Audit Period',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Verify header title
      expect(find.text('Select Audit Period'), findsOneWidget);
      // Verify quick presets
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('7 Days'), findsOneWidget);
      expect(find.text('30 Days'), findsOneWidget);
      expect(find.text('This Month'), findsOneWidget);

      // Verify month navigation and Month display
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      // Test month navigation
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('November 2026'), findsOneWidget);

      // Test preset tapping (Today)
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();

      // Apply
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Dialog closed and result returned
      expect(find.byType(ThqCompactDateRangeDialog), findsNothing);
      expect(result, isNotNull);
      final now = DateTime.now();
      expect(result!.start.day, now.day);
      expect(result!.start.month, now.month);
    });

    testWidgets('cancel dismisses without changing range', (tester) async {
      DateTimeRange? result;
      final initial = DateTimeRange(
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 15),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showThqCompactDateRangePicker(
                    context: context,
                    initialRange: initial,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(ThqCompactDateRangeDialog), findsNothing);
      expect(result, isNull);
    });
  });
}
