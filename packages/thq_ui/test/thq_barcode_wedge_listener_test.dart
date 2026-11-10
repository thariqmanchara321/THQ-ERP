import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LogicalKeyboardKey charToKey(String char) {
    return switch (char.toUpperCase()) {
      '0' => LogicalKeyboardKey.digit0,
      '1' => LogicalKeyboardKey.digit1,
      '2' => LogicalKeyboardKey.digit2,
      '3' => LogicalKeyboardKey.digit3,
      '4' => LogicalKeyboardKey.digit4,
      '5' => LogicalKeyboardKey.digit5,
      '6' => LogicalKeyboardKey.digit6,
      '7' => LogicalKeyboardKey.digit7,
      '8' => LogicalKeyboardKey.digit8,
      '9' => LogicalKeyboardKey.digit9,
      'A' => LogicalKeyboardKey.keyA,
      'B' => LogicalKeyboardKey.keyB,
      'C' => LogicalKeyboardKey.keyC,
      'D' => LogicalKeyboardKey.keyD,
      'E' => LogicalKeyboardKey.keyE,
      'O' => LogicalKeyboardKey.keyO,
      'T' => LogicalKeyboardKey.keyT,
      '-' => LogicalKeyboardKey.minus,
      _ => LogicalKeyboardKey.space,
    };
  }

  group('ThqBarcodeWedgeListener Widget Tests', () {
    late DateTime fakeClock;
    DateTime clock() => fakeClock;

    setUp(() {
      fakeClock = DateTime.utc(2026, 11, 10, 10, 0, 0);
    });

    testWidgets('Rapid keystrokes followed by Enter trigger onScan and controller', (tester) async {
      final controller = SmartScannerController();
      controller.start();
      String? scannedCode;
      ScannerSource? scannedSource;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThqBarcodeWedgeListener(
              controller: controller,
              clockSupplier: clock,
              interCharacterTimeout: const Duration(milliseconds: 50),
              onScan: (code, source) {
                scannedCode = code;
                scannedSource = source;
              },
              child: const Center(child: Text('Main Content')),
            ),
          ),
        ),
      );

      // Simulate scanner typing '890123' with 10ms intervals, then Enter
      const input = '890123';
      for (var i = 0; i < input.length; i++) {
        fakeClock = fakeClock.add(const Duration(milliseconds: 10));
        await tester.sendKeyEvent(
          charToKey(input[i]),
          character: input[i],
        );
        await tester.pump();
      }

      fakeClock = fakeClock.add(const Duration(milliseconds: 10));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(scannedCode, equals('890123'));
      expect(scannedSource, equals(ScannerSource.usb));
      expect(controller.latestResult?.normalizedValue, equals('890123'));
      expect(controller.history.length, equals(1));
    });

    testWidgets('Slow typing exceeding interCharacterTimeout does not trigger scan', (tester) async {
      String? scannedCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThqBarcodeWedgeListener(
              clockSupplier: clock,
              interCharacterTimeout: const Duration(milliseconds: 40),
              onScan: (code, source) => scannedCode = code,
              child: const SizedBox(),
            ),
          ),
        ),
      );

      // Keystroke 1
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
      await tester.pump();

      // Delay 150ms (human typing)
      fakeClock = fakeClock.add(const Duration(milliseconds: 150));

      // Keystroke 2
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
      await tester.pump();

      fakeClock = fakeClock.add(const Duration(milliseconds: 10));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // Buffer was reset by the slow delay, remaining was just '2' (< minBarcodeLength 3)
      expect(scannedCode, isNull);
    });

    testWidgets('Tab terminator triggers scan when acceptTabTerminator is true', (tester) async {
      String? scannedCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThqBarcodeWedgeListener(
              clockSupplier: clock,
              acceptTabTerminator: true,
              onScan: (code, _) => scannedCode = code,
              child: const SizedBox(),
            ),
          ),
        ),
      );

      const input = 'TAB-CODE';
      for (var i = 0; i < input.length; i++) {
        fakeClock = fakeClock.add(const Duration(milliseconds: 10));
        await tester.sendKeyEvent(
          charToKey(input[i]),
          character: input[i],
        );
        await tester.pump();
      }

      fakeClock = fakeClock.add(const Duration(milliseconds: 10));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(scannedCode, equals('TAB-CODE'));
    });

    testWidgets('Does not hijack typing when an EditableText has focus', (tester) async {
      String? scannedCode;
      final textController = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThqBarcodeWedgeListener(
              clockSupplier: clock,
              interceptWhenEditableFocused: false,
              onScan: (code, _) => scannedCode = code,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: textController,
                  autofocus: true,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Type directly into focused TextField
      await tester.enterText(find.byType(TextField), 'Manual Search Note');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // Wedge listener must NOT intercept normal textfield input
      expect(scannedCode, isNull);
      expect(textController.text, equals('Manual Search Note'));
    });

    testWidgets('Disabled listener ignores all keystrokes', (tester) async {
      String? scannedCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThqBarcodeWedgeListener(
              enabled: false,
              clockSupplier: clock,
              onScan: (code, _) => scannedCode = code,
              child: const SizedBox(),
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3, character: '3');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4, character: '4');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(scannedCode, isNull);
    });

    testWidgets('Minimum length constraint rejects short inputs', (tester) async {
      String? scannedCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThqBarcodeWedgeListener(
              minBarcodeLength: 5,
              clockSupplier: clock,
              onScan: (code, _) => scannedCode = code,
              child: const SizedBox(),
            ),
          ),
        ),
      );

      // Send 3 characters only
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'A');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'B');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC, character: 'C');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(scannedCode, isNull);
    });
  });
}
