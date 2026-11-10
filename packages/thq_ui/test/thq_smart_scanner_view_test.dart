import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  group('ThqSmartScannerView Widget Tests', () {
    testWidgets('Renders desktop guidance card when camera is unsupported on desktop OS', (tester) async {
      var closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThqSmartScannerView(
              instructionText: 'Custom Scanning Instructions',
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      // On Windows (where test runs), camera fallback is rendered
      expect(find.text('Camera Scanner Unavailable on Desktop'), findsOneWidget);
      expect(
        find.textContaining('Windows desktop uses USB or Bluetooth barcode scanners'),
        findsOneWidget,
      );
      expect(find.text('Close'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pump();
      expect(closed, isTrue);
    });

    testWidgets('Integrates with SmartScannerController cleanly', (tester) async {
      final controller = SmartScannerController();
      controller.start();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThqSmartScannerView(
              controller: controller,
            ),
          ),
        ),
      );

      expect(controller.status, equals(ScannerStatus.scanning));
      expect(controller.isDisposed, isFalse);

      controller.dispose();
      expect(controller.isDisposed, isTrue);
    });
  });
}
