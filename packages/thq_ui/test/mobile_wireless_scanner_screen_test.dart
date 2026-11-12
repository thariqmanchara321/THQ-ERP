import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  group('ThqMobileWirelessScannerScreen Widget Tests', () {
    late MockWirelessScannerTransport mockTransport;
    late WirelessScannerPairingPayload testPayload;

    setUp(() {
      mockTransport = MockWirelessScannerTransport();
      testPayload = WirelessScannerPairingPayload(
        version: 1,
        sessionId: 'session-xyz-123',
        tenantId: 'tenant-demo',
        locationId: 'loc-main',
        hostDeviceName: 'POS-Cashier-PC',
        handshakeSecret: 'sec-abcdef1234567890abcdef1234567890',
        channelName: 'thq_scan_tenant-demo_session-xyz-123',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      );
    });

    tearDown(() {
      mockTransport.dispose();
    });

    testWidgets('renders in pairing mode when not paired', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ThqMobileWirelessScannerScreen(
            tenantId: 'tenant-demo',
            deviceName: 'Pixel 8 Pro',
            deviceId: 'dev-pixel-123',
            transport: mockTransport,
          ),
        ),
      );

      expect(find.text('Wireless Scanner Pairing'), findsOneWidget);
      expect(find.text('Scan QR on THQ Desktop screen to pair'), findsOneWidget);
    });

    testWidgets('direct payload joins session and displays connected header',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ThqMobileWirelessScannerScreen(
            tenantId: 'tenant-demo',
            deviceName: 'Pixel 8 Pro',
            deviceId: 'dev-pixel-123',
            transport: mockTransport,
            initialPayload: testPayload,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('POS-Cashier-PC'), findsOneWidget);
      expect(find.text('Point camera at product barcodes'), findsOneWidget);
      expect(find.byTooltip('Manual Barcode Entry'), findsOneWidget);
      expect(find.byTooltip('Scan History'), findsOneWidget);
    });

    testWidgets('manual barcode entry transmits scan and shows ACK banner',
        (tester) async {
      mockTransport.autoAck = true;
      mockTransport.autoAckProductName = 'Amoxicillin 500mg (Strip)';

      await tester.pumpWidget(
        MaterialApp(
          home: ThqMobileWirelessScannerScreen(
            tenantId: 'tenant-demo',
            deviceName: 'Pixel 8 Pro',
            deviceId: 'dev-pixel-123',
            transport: mockTransport,
            initialPayload: testPayload,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Open manual entry dialog
      await tester.tap(find.byTooltip('Manual Barcode Entry'));
      await tester.pumpAndSettle();

      expect(find.text('Manual Barcode Entry'), findsOneWidget);

      // Enter barcode
      await tester.enterText(find.byType(TextField), '8901234567890');
      await tester.tap(find.text('Send to PC'));
      await tester.pumpAndSettle();

      // Wait for auto-ACK from mock transport
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Amoxicillin 500mg (Strip)'), findsOneWidget);

      // Open history
      await tester.tap(find.byTooltip('Scan History'));
      await tester.pumpAndSettle();

      expect(find.text('8901234567890'), findsOneWidget);
      expect(find.text('Amoxicillin 500mg (Strip)'), findsWidgets);
    });

    testWidgets('unpair confirmation disconnects cleanly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ThqMobileWirelessScannerScreen(
            tenantId: 'tenant-demo',
            deviceName: 'Pixel 8 Pro',
            deviceId: 'dev-pixel-123',
            transport: mockTransport,
            initialPayload: testPayload,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('POS-Cashier-PC'), findsOneWidget);

      // Tap unpair icon
      await tester.tap(find.byTooltip('Disconnect'));
      await tester.pumpAndSettle();

      expect(find.text('Disconnect Scanner?'), findsOneWidget);
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      // Should be back to pairing mode
      expect(find.text('Wireless Scanner Pairing'), findsOneWidget);
    });
  });
}
