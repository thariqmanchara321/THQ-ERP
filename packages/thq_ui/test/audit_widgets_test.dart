import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('audit table keeps links usable at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? opened;
      final row = {
        'reference':
            'A very long journal reference and account name for layout',
        'amount': -1234.5,
        'margin': 12.5,
        'status': 'high_risk',
        'id': 'journal-1',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuditTable(
              columns: const [
                AuditColumn('reference', 'Reference', flex: 4),
                AuditColumn('amount', 'Balance', numeric: true),
                AuditColumn(
                  'margin',
                  'Margin',
                  numeric: true,
                  format: 'percent',
                  compact: false,
                ),
                AuditColumn('status', 'Status'),
              ],
              rows: [row],
              onOpen: (value) => opened = value,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('−₹1,234.50'), findsOneWidget);
      expect(find.text('High risk'), findsOneWidget);
      expect(find.text('12.50%'), width < 720 ? findsNothing : findsOneWidget);
      await tester.tap(find.text(row['reference'] as String));
      await tester.pump();
      expect(opened?['id'], 'journal-1');
    });
  }
  testWidgets(
    'evidence preserves zero and false, suppresses implementation identifiers',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuditEvidence(
              title: 'Evidence',
              expanded: true,
              value: {
                'amount': 0,
                'approved': false,
                'reason': 'Count verified',
                'actor_user_id': '9947f931-26d4-4f5d-812b-6c8c9398d280',
                'event_hash': 'hidden-hash',
              },
            ),
          ),
        ),
      );
      expect(find.text('₹0.00'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      expect(find.text('Count verified'), findsOneWidget);
      expect(find.text('hidden-hash'), findsNothing);
      expect(find.text('9947f931-26d4-4f5d-812b-6c8c9398d280'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
