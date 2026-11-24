import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  group('ThqDateRangeSelector Tests', () {
    testWidgets('renders preset chips on wide display and updates range', (tester) async {
      DateTimeRange currentRange = DateTimeRange(
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 24, 23, 59, 59),
      );
      ThqDatePreset currentPreset = ThqDatePreset.days30;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800,
                child: ThqDateRangeSelector(
                  selectedRange: currentRange,
                  activePreset: currentPreset,
                  onRangeChanged: (range) => currentRange = range,
                  onPresetChanged: (preset) => currentPreset = preset,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('7 Days'), findsOneWidget);
      expect(find.text('30 Days'), findsOneWidget);
      expect(find.text('90 Days'), findsOneWidget);

      // Tap '7 Days' preset
      await tester.tap(find.text('7 Days'));
      await tester.pumpAndSettle();

      expect(currentPreset, equals(ThqDatePreset.days7));
      expect(currentRange.end.difference(currentRange.start).inDays, equals(6));
    });

    testWidgets('renders compact dropdown on narrow display', (tester) async {
      final currentRange = DateTimeRange(
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 24, 23, 59, 59),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: ThqDateRangeSelector(
                  selectedRange: currentRange,
                  activePreset: ThqDatePreset.days30,
                  onRangeChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      // In narrow display, DropdownButton is used
      expect(find.byType(DropdownButton<ThqDatePreset>), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    });
  });

  group('ThqResponsiveTable Tests', () {
    final columns = const [
      ThqResponsiveColumn(title: 'Product', flex: 3),
      ThqResponsiveColumn(title: 'SKU', flex: 2),
      ThqResponsiveColumn(title: 'Available', flex: 1, isNumeric: true),
    ];

    final rows = [
      ThqResponsiveRow(
        cardTitle: const Text('Widget A'),
        cardFields: const [('SKU', 'SKU-001'), ('Available', '42')],
        cells: const [Text('Widget A'), Text('SKU-001'), Text('42')],
      ),
      ThqResponsiveRow(
        cardTitle: const Text('Widget B'),
        cardFields: const [('SKU', 'SKU-002'), ('Available', '10')],
        cells: const [Text('Widget B'), Text('SKU-002'), Text('10')],
      ),
    ];

    testWidgets('renders as table on wide viewport', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 900,
                child: ThqResponsiveTable(
                  columns: columns,
                  rows: rows,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Product'), findsOneWidget);
      expect(find.text('SKU'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Widget A'), findsOneWidget);
      expect(find.text('SKU-001'), findsOneWidget);
    });

    testWidgets('renders as cards on mobile viewport without horizontal scroll', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: ThqResponsiveTable(
                  columns: columns,
                  rows: rows,
                ),
              ),
            ),
          ),
        ),
      );

      // On narrow viewport, cards are used
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.text('Widget A'), findsOneWidget);
      expect(find.text('SKU: '), findsNWidgets(2));
    });
  });
}
