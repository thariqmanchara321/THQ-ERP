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

    testWidgets('acknowledgement timeout marks pending scan as failed after 5s',
        (tester) async {
      // Disable autoAck so the scan stays pending until timeout
      mockTransport.autoAck = false;

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

      // Enter a barcode manually
      await tester.tap(find.byTooltip('Manual Barcode Entry'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '8901234567890');
      await tester.tap(find.text('Send to PC'));
      await tester.pumpAndSettle();

      // Fast forward past 5-second ACK timeout
      await tester.pump(const Duration(seconds: 6));

      // Open history drawer
      await tester.tap(find.byTooltip('Scan History'));
      await tester.pumpAndSettle();

      // Status should have transitioned to failed
      expect(find.text('8901234567890'), findsOneWidget);
      expect(find.textContaining('failed'), findsOneWidget);
    });

    testWidgets('duplicate ACK displays duplicate scan suppressed banner',
        (tester) async {
      mockTransport.autoAck = false;

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

      // Enter barcode
      await tester.tap(find.byTooltip('Manual Barcode Entry'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '8901234567890');
      await tester.tap(find.text('Send to PC'));
      await tester.pumpAndSettle();

      // Simulate duplicate ACK received from desktop
      final dupAck = WirelessScanAck.create(
        messageId: 'msg-mock-dup',
        sessionId: testPayload.sessionId,
        success: true,
        receivedCode: '8901234567890',
        handshakeSecret: testPayload.handshakeSecret,
        isDuplicate: true,
        productName: 'Duplicate scan suppressed',
      );

      mockTransport.simulateIncomingAck(dupAck);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Duplicate Scan Suppressed'), findsOneWidget);

      // Flush remaining cooldown timer
      await tester.pump(const Duration(seconds: 1));
    });
  });
}

