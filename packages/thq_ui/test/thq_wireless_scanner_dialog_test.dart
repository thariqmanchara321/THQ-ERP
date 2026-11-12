import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  group('ThqPairingQrView Tests', () {
    testWidgets('renders QR canvas correctly with valid payload',
        (tester) async {
      const qrData =
          'thq-pair://v1?sid=s123&t=tenant_abc&loc=loc_1&d=Desktop&sec=secret123&ch=thq_scan_ch&exp=9999999999';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ThqPairingQrView(
                data: qrData,
                size: 200,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ThqPairingQrView), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('displays fallback text when data is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ThqPairingQrView(
                data: '',
                size: 200,
              ),
            ),
          ),
        ),
      );

      expect(find.text('No pairing data'), findsOneWidget);
    });
  });

  group('ThqWirelessScannerDialog Tests', () {
    testWidgets(
        'displays pairing QR and instructions when in pairingPending state',
        (tester) async {
      final transport = MockWirelessScannerTransport();
      final coordinator = WirelessScannerCoordinator(transport: transport);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ThqWirelessScannerDialog.show(
                    context: context,
                    coordinator: coordinator,
                    tenantId: 'tenant_test',
                    hostDeviceName: 'POS-Terminal-1',
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Phone-to-PC Wireless Scanner'), findsOneWidget);
      expect(find.text('Pair with mobile scanner'), findsOneWidget);
      expect(find.byType(ThqPairingQrView), findsOneWidget);
      expect(find.text('How to connect:'), findsOneWidget);
      expect(find.text('Open THQ Mobile on your phone'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      coordinator.dispose();
    });

    testWidgets(
        'transitions to connected view when phone connects and displays device info',
        (tester) async {
      final transport = MockWirelessScannerTransport();
      final coordinator = WirelessScannerCoordinator(transport: transport);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ThqWirelessScannerDialog.show(
                    context: context,
                    coordinator: coordinator,
                    tenantId: 'tenant_test',
                    hostDeviceName: 'POS-Terminal-1',
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Simulate phone joining
      final payload = coordinator.currentPayload!;
      await transport.joinSession(
        payload: payload,
        phoneDeviceId: 'phone-galaxy-s22',
        phoneDeviceName: 'Galaxy S22 Assistant',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Galaxy S22 Assistant'), findsOneWidget);
      expect(find.text('Paired and ready to scan'), findsOneWidget);
      expect(find.text('Unpair Phone'), findsOneWidget);
      expect(find.text('phone-galaxy-s22'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      coordinator.dispose();
    });

    testWidgets('unpair button resets session to pairing state',
        (tester) async {
      final transport = MockWirelessScannerTransport();
      final coordinator = WirelessScannerCoordinator(transport: transport);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ThqWirelessScannerDialog.show(
                    context: context,
                    coordinator: coordinator,
                    tenantId: 'tenant_test',
                    hostDeviceName: 'POS-Terminal-1',
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final payload = coordinator.currentPayload!;
      await transport.joinSession(
        payload: payload,
        phoneDeviceId: 'phone-galaxy-s22',
        phoneDeviceName: 'Galaxy S22 Assistant',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Unpair Phone'), findsOneWidget);
      await tester.tap(find.text('Unpair Phone'));
      await tester.pumpAndSettle();

      // Should be back to pairing mode
      expect(find.text('Pair with mobile scanner'), findsOneWidget);
      expect(find.byType(ThqPairingQrView), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      coordinator.dispose();
    });
  });
}
