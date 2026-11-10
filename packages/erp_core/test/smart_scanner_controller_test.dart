import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmartScannerController Tests', () {
    late DateTime fakeTime;
    DateTime clock() => fakeTime;

    setUp(() {
      fakeTime = DateTime.utc(2026, 11, 10, 10, 0, 0);
    });

    test('Initial state is idle with empty history and default configuration', () {
      final controller = SmartScannerController(clockSupplier: clock);

      expect(controller.status, equals(ScannerStatus.idle));
      expect(controller.history, isEmpty);
      expect(controller.latestResult, isNull);
      expect(controller.isDisposed, isFalse);
      expect(controller.lastErrorMessage, isNull);
      expect(controller.configuration.mode, equals(ScannerMode.continuous));
      expect(controller.configuration.allowDuplicates, isFalse);
    });

    test('Lifecycle transitions: start, pause, resume, stop, reset', () async {
      final controller = SmartScannerController(clockSupplier: clock);
      final statuses = <ScannerStatus>[];
      final sub = controller.statusStream.listen(statuses.add);

      controller.start();
      expect(controller.status, equals(ScannerStatus.scanning));

      controller.pause();
      expect(controller.status, equals(ScannerStatus.paused));

      controller.resume();
      expect(controller.status, equals(ScannerStatus.scanning));

      controller.stop();
      expect(controller.status, equals(ScannerStatus.stopped));

      controller.reset();
      expect(controller.status, equals(ScannerStatus.ready));

      await Future<void>.delayed(Duration.zero);
      expect(statuses, equals([
        ScannerStatus.scanning,
        ScannerStatus.paused,
        ScannerStatus.scanning,
        ScannerStatus.stopped,
        ScannerStatus.ready,
      ]));
      await sub.cancel();
    });

    test('Single scan mode accepts first scan then pauses automatically', () async {
      final controller = SmartScannerController(
        configuration: ScannerConfiguration.single(),
        clockSupplier: clock,
      );
      controller.start();

      final first = controller.submitScan('8901234567890', format: SmartBarcodeFormat.ean13);
      expect(first, isNotNull);
      expect(first!.normalizedValue, equals('8901234567890'));
      expect(controller.status, equals(ScannerStatus.paused));

      // Attempt second scan while paused by single mode
      final second = controller.submitScan('8909876543210');
      expect(second, isNull);
      expect(controller.history.length, equals(1));

      // Explicitly resume
      controller.resume();
      expect(controller.status, equals(ScannerStatus.scanning));

      final third = controller.submitScan('8909876543210');
      expect(third, isNotNull);
      expect(controller.history.length, equals(2));
      expect(controller.status, equals(ScannerStatus.paused));
    });

    test('Continuous scan mode accepts sequential distinct scans', () {
      final controller = SmartScannerController(
        configuration: const ScannerConfiguration(mode: ScannerMode.continuous),
        clockSupplier: clock,
      );
      controller.start();

      final r1 = controller.submitScan('BARCODE-001');
      final r2 = controller.submitScan('BARCODE-002');
      final r3 = controller.submitScan('BARCODE-003');

      expect(r1, isNotNull);
      expect(r2, isNotNull);
      expect(r3, isNotNull);
      expect(controller.history.length, equals(3));
      expect(controller.latestResult?.normalizedValue, equals('BARCODE-003'));
      expect(controller.status, equals(ScannerStatus.scanning));
    });

    test('Duplicate suppression suppresses burst frames within duration', () {
      final controller = SmartScannerController(
        configuration: const ScannerConfiguration(
          mode: ScannerMode.continuous,
          duplicateSuppressionDuration: Duration(milliseconds: 1000),
          allowDuplicates: false,
        ),
        clockSupplier: clock,
      );
      controller.start();

      // Scan at T = 0ms
      final r1 = controller.submitScan('8901234567890');
      expect(r1, isNotNull);

      // Duplicate scan at T + 200ms -> suppressed
      fakeTime = fakeTime.add(const Duration(milliseconds: 200));
      final r2 = controller.submitScan('8901234567890');
      expect(r2, isNull);
      expect(controller.history.length, equals(1));

      // Duplicate scan at T + 900ms -> still suppressed (< 1000ms)
      fakeTime = fakeTime.add(const Duration(milliseconds: 700));
      final r3 = controller.submitScan('8901234567890');
      expect(r3, isNull);
      expect(controller.history.length, equals(1));

      // Scan after window (T + 1200ms) -> accepted
      fakeTime = fakeTime.add(const Duration(milliseconds: 300));
      final r4 = controller.submitScan('8901234567890');
      expect(r4, isNotNull);
      expect(controller.history.length, equals(2));
    });

    test('allowDuplicates: true accepts identical scans immediately without delay', () {
      final controller = SmartScannerController(
        configuration: const ScannerConfiguration(
          mode: ScannerMode.continuous,
          allowDuplicates: true,
        ),
        clockSupplier: clock,
      );
      controller.start();

      final r1 = controller.submitScan('REPEAT-BARCODE');
      final r2 = controller.submitScan('REPEAT-BARCODE');
      final r3 = controller.submitScan('REPEAT-BARCODE');

      expect(r1, isNotNull);
      expect(r2, isNotNull);
      expect(r3, isNotNull);
      expect(controller.history.length, equals(3));
    });

    test('Leading zeros are strictly preserved and not truncated', () {
      final controller = SmartScannerController(clockSupplier: clock);
      controller.start();

      final result = controller.submitScan('00012345000', format: SmartBarcodeFormat.ean13);
      expect(result, isNotNull);
      expect(result!.rawValue, equals('00012345000'));
      expect(result.normalizedValue, equals('00012345000'));
      expect(result.normalizedValue.startsWith('000'), isTrue);
    });

    test('Rejects empty or whitespace-only inputs', () {
      final controller = SmartScannerController(clockSupplier: clock);
      controller.start();

      final r1 = controller.submitScan('');
      expect(r1, isNull);
      expect(controller.lastErrorMessage, contains('empty'));

      final r2 = controller.submitScan('   \t\n  ');
      expect(r2, isNull);
      expect(controller.history, isEmpty);
    });

    test('Length constraints enforce min and max bounds', () {
      final controller = SmartScannerController(
        configuration: const ScannerConfiguration(
          minInputLength: 4,
          maxInputLength: 10,
        ),
        clockSupplier: clock,
      );
      controller.start();

      // Too short
      final short = controller.submitScan('ABC');
      expect(short, isNull);
      expect(controller.lastErrorMessage, contains('too short'));

      // Valid
      final valid = controller.submitScan('ABCD');
      expect(valid, isNotNull);

      // Too long
      final long = controller.submitScan('0123456789012345');
      expect(long, isNull);
      expect(controller.lastErrorMessage, contains('maximum length'));
    });

    test('History limit trims oldest scans to maxHistorySize', () {
      final controller = SmartScannerController(
        configuration: const ScannerConfiguration(
          maxHistorySize: 3,
          allowDuplicates: true,
        ),
        clockSupplier: clock,
      );
      controller.start();

      controller.submitScan('ITEM-1');
      controller.submitScan('ITEM-2');
      controller.submitScan('ITEM-3');
      controller.submitScan('ITEM-4');
      controller.submitScan('ITEM-5');

      expect(controller.history.length, equals(3));
      // Newest first
      expect(controller.history[0].normalizedValue, equals('ITEM-5'));
      expect(controller.history[1].normalizedValue, equals('ITEM-4'));
      expect(controller.history[2].normalizedValue, equals('ITEM-3'));

      controller.clearHistory();
      expect(controller.history, isEmpty);
      expect(controller.latestResult, isNull);
    });

    test('Stream emissions dispatch scan results in real-time', () async {
      final controller = SmartScannerController(clockSupplier: clock);
      controller.start();

      final emitted = <SmartScanResult>[];
      final sub = controller.scans.listen(emitted.add);

      controller.submitScan('STREAM-TEST-1', source: ScannerSource.usb);
      controller.submitScan('STREAM-TEST-2', source: ScannerSource.bluetooth);

      await Future<void>.delayed(Duration.zero);
      expect(emitted.length, equals(2));
      expect(emitted[0].source, equals(ScannerSource.usb));
      expect(emitted[1].source, equals(ScannerSource.bluetooth));

      await sub.cancel();
    });

    test('Disposal closes streams and throws StateError on subsequent calls', () {
      final controller = SmartScannerController(clockSupplier: clock);
      controller.start();
      controller.submitScan('SCAN-BEFORE-DISPOSE');

      controller.dispose();
      expect(controller.isDisposed, isTrue);
      expect(controller.status, equals(ScannerStatus.stopped));
      expect(controller.history, isEmpty);

      // Repeated dispose is safe
      controller.dispose();

      expect(() => controller.start(), throwsStateError);
      expect(() => controller.submitScan('CODE'), throwsStateError);
      expect(() => controller.clearHistory(), throwsStateError);
    });

    test('SmartBarcodeFormat parses raw symbology names accurately', () {
      expect(SmartBarcodeFormat.fromRawName('ean13'), equals(SmartBarcodeFormat.ean13));
      expect(SmartBarcodeFormat.fromRawName('EAN-13'), equals(SmartBarcodeFormat.ean13));
      expect(SmartBarcodeFormat.fromRawName('qr_code'), equals(SmartBarcodeFormat.qrCode));
      expect(SmartBarcodeFormat.fromRawName('QR'), equals(SmartBarcodeFormat.qrCode));
      expect(SmartBarcodeFormat.fromRawName('CODE_128'), equals(SmartBarcodeFormat.code128));
      expect(SmartBarcodeFormat.fromRawName('unknown_custom'), equals(SmartBarcodeFormat.unknown));
      expect(SmartBarcodeFormat.fromRawName(null), equals(SmartBarcodeFormat.unknown));
    });

    test('SmartScanResult serialization roundtrips cleanly', () {
      final original = SmartScanResult.valid(
        rawValue: '012345678905',
        format: SmartBarcodeFormat.ean13,
        source: ScannerSource.usb,
        timestamp: DateTime.utc(2026, 11, 10, 12, 30),
        sessionId: 'session-42',
        deviceId: 'term-01',
      );

      final map = original.toMap();
      final revived = SmartScanResult.fromMap(map);

      expect(revived, equals(original));
      expect(revived.normalizedValue, equals('012345678905'));
      expect(revived.format, equals(SmartBarcodeFormat.ean13));
      expect(revived.source, equals(ScannerSource.usb));
      expect(revived.sessionId, equals('session-42'));
    });
  });
}
