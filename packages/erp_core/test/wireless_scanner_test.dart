import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BarcodeAccuracyVerifier Symbology Integrity Tests', () {
    test('Valid EAN-13 passes check digit verification with leading zero preserved', () {
      // 0012345678905 has leading zeros and valid check digit
      const validCode = '8901234567890';
      final result = BarcodeAccuracyVerifier.verify(
        rawValue: validCode,
        format: SmartBarcodeFormat.ean13,
      );

      expect(result.isValid, isTrue);
      expect(result.rawCode, validCode);
      expect(result.format, SmartBarcodeFormat.ean13);
      expect(result.rejectionReason, isNull);
    });

    test('EAN-13 with corrupted check digit is rejected as glitched camera read', () {
      // Last digit 9 is invalid for 890123456789 (expected 0)
      const corruptedCode = '8901234567899';
      final result = BarcodeAccuracyVerifier.verify(
        rawValue: corruptedCode,
        format: SmartBarcodeFormat.ean13,
      );

      expect(result.isValid, isFalse);
      expect(result.rejectionReason, contains('EAN-13 check digit mismatch'));
    });

    test('Truncated 11 or 12 digit camera frame marked as EAN-13 is rejected', () {
      const truncatedCode = '89012345678';
      final result = BarcodeAccuracyVerifier.verify(
        rawValue: truncatedCode,
        format: SmartBarcodeFormat.ean13,
      );

      expect(result.isValid, isFalse);
      expect(result.rejectionReason, contains('requires exactly 13 numeric digits'));
    });

    test('Valid UPC-A passes check digit verification', () {
      const validUpc = '012345678905';
      final result = BarcodeAccuracyVerifier.verify(
        rawValue: validUpc,
        format: SmartBarcodeFormat.upcA,
      );

      expect(result.isValid, isTrue);
      expect(result.rawCode, validUpc);
      expect(result.format, SmartBarcodeFormat.upcA);
    });

    test('UPC-A with wrong check digit is rejected', () {
      const corruptedUpc = '012345678904';
      final result = BarcodeAccuracyVerifier.verify(
        rawValue: corruptedUpc,
        format: SmartBarcodeFormat.upcA,
      );

      expect(result.isValid, isFalse);
      expect(result.rejectionReason, contains('UPC-A check digit mismatch'));
    });

    test('Code 128 accepts valid printable ASCII and rejects non-printable chars', () {
      const validCode128 = 'SKU-CEMENT-50KG-BAG';
      final validResult = BarcodeAccuracyVerifier.verify(
        rawValue: validCode128,
        format: SmartBarcodeFormat.code128,
      );
      expect(validResult.isValid, isTrue);

      final invalidCode = 'SKU-TEST\x07BAD';
      final invalidResult = BarcodeAccuracyVerifier.verify(
        rawValue: invalidCode,
        format: SmartBarcodeFormat.code128,
      );
      expect(invalidResult.isValid, isFalse);
    });

    test('QR Code payload is validated without alteration', () {
      const qrPayload = 'THQ:PRODUCT:var-001:SKU-001';
      final result = BarcodeAccuracyVerifier.verify(
        rawValue: qrPayload,
        format: SmartBarcodeFormat.qrCode,
      );

      expect(result.isValid, isTrue);
      expect(result.rawCode, qrPayload);
    });
  });

  group('WirelessScannerPairingPayload Tests', () {
    const tenantId = 'tenant-test-123';
    final now = DateTime.now();

    test('Serializes to QR string and deserializes accurately', () {
      final payload = WirelessScannerPairingPayload(
        version: 1,
        sessionId: 'session-abc-001',
        tenantId: tenantId,
        locationId: 'loc-wh-1',
        hostDeviceName: 'POS Desktop 1',
        handshakeSecret: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
        channelName: 'thq:scan:tenant-test-123:session-abc-001',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 10)),
      );

      final qrString = payload.toQrString();
      expect(qrString, contains('thq_wireless_pair'));
      expect(qrString, contains('session-abc-001'));

      final parsed = WirelessScannerPairingPayload.fromQrString(qrString);
      expect(parsed.version, 1);
      expect(parsed.sessionId, 'session-abc-001');
      expect(parsed.tenantId, tenantId);
      expect(parsed.locationId, 'loc-wh-1');
      expect(parsed.hostDeviceName, 'POS Desktop 1');
      expect(parsed.handshakeSecret, 'a1b2c3d4e5f60718293a4b5c6d7e8f90');
      expect(parsed.isExpired, isFalse);
    });

    test('Expired QR code throws FormatException', () {
      final expiredPayload = WirelessScannerPairingPayload(
        version: 1,
        sessionId: 'session-expired',
        tenantId: tenantId,
        hostDeviceName: 'POS Desktop 1',
        handshakeSecret: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
        channelName: 'thq:scan:tenant-test-123:session-expired',
        createdAt: now.subtract(const Duration(minutes: 15)),
        expiresAt: now.subtract(const Duration(minutes: 5)),
      );

      final qrString = expiredPayload.toQrString();
      expect(
        () => WirelessScannerPairingPayload.fromQrString(qrString),
        throwsA(isA<FormatException>()),
      );
    });

    test('Invalid non-pairing QR throws FormatException', () {
      expect(
        () => WirelessScannerPairingPayload.fromQrString('https://google.com'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('WirelessScanMessage Security & HMAC Tests', () {
    const secret = 'super-secure-handshake-secret-128';

    test('HMAC-SHA256 signature validates packet origin', () {
      final msg = WirelessScanMessage(
        messageId: 'msg-001',
        sessionId: 'session-001',
        tenantId: 'tenant-001',
        senderDeviceId: 'phone-pixel-7',
        senderDeviceName: 'Pixel 7 Pro',
        rawCode: '0012345678905', // Leading zeros preserved
        format: SmartBarcodeFormat.ean13,
        timestamp: DateTime.now(),
        authSignature: WirelessScanMessage.computeSignature(
          sessionId: 'session-001',
          messageId: 'msg-001',
          rawCode: '0012345678905',
          handshakeSecret: secret,
        ),
      );

      expect(msg.verifySignature(secret), isTrue);
      expect(msg.verifySignature('wrong-secret'), isFalse);
    });

    test('Tampering with barcode payload invalidates signature', () {
      final msg = WirelessScanMessage(
        messageId: 'msg-001',
        sessionId: 'session-001',
        tenantId: 'tenant-001',
        senderDeviceId: 'phone-pixel-7',
        senderDeviceName: 'Pixel 7 Pro',
        rawCode: '8901234567890',
        format: SmartBarcodeFormat.ean13,
        timestamp: DateTime.now(),
        authSignature: WirelessScanMessage.computeSignature(
          sessionId: 'session-001',
          messageId: 'msg-001',
          rawCode: '8901234567890',
          handshakeSecret: secret,
        ),
      );

      // Tampered code
      final tampered = WirelessScanMessage(
        messageId: msg.messageId,
        sessionId: msg.sessionId,
        tenantId: msg.tenantId,
        senderDeviceId: msg.senderDeviceId,
        senderDeviceName: msg.senderDeviceName,
        rawCode: '8901234567899', // Altered barcode
        format: msg.format,
        timestamp: msg.timestamp,
        authSignature: msg.authSignature,
      );

      expect(tampered.verifySignature(secret), isFalse);
    });
  });

  group('WirelessScannerCoordinator & Transport Tests', () {
    late MockWirelessScannerTransport transport;
    late WirelessScannerCoordinator coordinator;

    const tenantId = 'tenant-test-retail';

    setUp(() {
      transport = MockWirelessScannerTransport();
      coordinator = WirelessScannerCoordinator(
        transport: transport,
        duplicateSuppressionDuration: const Duration(milliseconds: 500),
      );
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('Desktop starts hosting and transitions to pairingPending state', () async {
      expect(coordinator.currentState, WirelessScannerState.disconnected);

      final payload = await coordinator.startHosting(
        tenantId: tenantId,
        locationId: 'loc-01',
        hostDeviceName: 'POS Counter 1',
      );

      expect(coordinator.currentState, WirelessScannerState.pairingPending);
      expect(payload.tenantId, tenantId);
      expect(payload.hostDeviceName, 'POS Counter 1');
      expect(payload.handshakeSecret.length, 32);
      expect(payload.isExpired, isFalse);
    });

    test('Mobile joins session and transitions state to connected', () async {
      final payload = await coordinator.startHosting(
        tenantId: tenantId,
        hostDeviceName: 'POS Counter 1',
      );

      final joined = await coordinator.joinAsScanner(
        payload: payload,
        deviceId: 'device-s23',
        deviceName: 'Samsung Galaxy S23',
      );

      expect(joined, isTrue);
      expect(coordinator.isConnected, isTrue);
      expect(coordinator.currentState, WirelessScannerState.connected);
      expect(coordinator.activeDevice?.deviceName, 'Samsung Galaxy S23');
    });

    test('Transmitted scan is received and exact string is preserved', () async {
      final payload = await coordinator.startHosting(
        tenantId: tenantId,
        hostDeviceName: 'POS Counter 1',
      );

      await coordinator.joinAsScanner(
        payload: payload,
        deviceId: 'device-pixel-8',
        deviceName: 'Pixel 8',
      );

      const exactCode = '008901234567890'; // Preserves leading zeros

      final receivedScans = <WirelessScanMessage>[];
      coordinator.scans.listen((s) => receivedScans.add(s));

      final scan = WirelessScanMessage(
        messageId: 'scan-uuid-001',
        sessionId: payload.sessionId,
        tenantId: tenantId,
        senderDeviceId: 'device-pixel-8',
        senderDeviceName: 'Pixel 8',
        rawCode: exactCode,
        format: SmartBarcodeFormat.ean13,
        timestamp: DateTime.now(),
        authSignature: WirelessScanMessage.computeSignature(
          sessionId: payload.sessionId,
          messageId: 'scan-uuid-001',
          rawCode: exactCode,
          handshakeSecret: payload.handshakeSecret,
        ),
      );

      final sent = await transport.sendScan(scan);
      expect(sent, isTrue);

      // Allow stream microtask to deliver
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(receivedScans.length, 1);
      expect(receivedScans.first.rawCode, exactCode);
      expect(receivedScans.first.format, SmartBarcodeFormat.ean13);
      expect(receivedScans.first.senderDeviceName, 'Pixel 8');
    });

    test('Duplicate suppression suppresses rapid identical scans within window', () async {
      final payload = await coordinator.startHosting(
        tenantId: tenantId,
        hostDeviceName: 'POS Counter 1',
      );

      await coordinator.joinAsScanner(
        payload: payload,
        deviceId: 'device-1',
        deviceName: 'Mobile 1',
      );

      final receivedScans = <WirelessScanMessage>[];
      coordinator.scans.listen((s) => receivedScans.add(s));

      const testCode = '8901234567890';

      WirelessScanMessage makeMsg(String id) => WirelessScanMessage(
            messageId: id,
            sessionId: payload.sessionId,
            tenantId: tenantId,
            senderDeviceId: 'device-1',
            senderDeviceName: 'Mobile 1',
            rawCode: testCode,
            format: SmartBarcodeFormat.ean13,
            timestamp: DateTime.now(),
            authSignature: WirelessScanMessage.computeSignature(
              sessionId: payload.sessionId,
              messageId: id,
              rawCode: testCode,
              handshakeSecret: payload.handshakeSecret,
            ),
          );

      // Send first scan
      await transport.sendScan(makeMsg('scan-01'));
      // Send second identical scan immediately (within 500ms window)
      await transport.sendScan(makeMsg('scan-02'));

      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Second identical scan should be suppressed
      expect(receivedScans.length, 1);

      // Different barcode should NOT be suppressed
      const differentCode = 'SKU-STEEL-12MM';
      final diffMsg = WirelessScanMessage(
        messageId: 'scan-03',
        sessionId: payload.sessionId,
        tenantId: tenantId,
        senderDeviceId: 'device-1',
        senderDeviceName: 'Mobile 1',
        rawCode: differentCode,
        format: SmartBarcodeFormat.code128,
        timestamp: DateTime.now(),
        authSignature: WirelessScanMessage.computeSignature(
          sessionId: payload.sessionId,
          messageId: 'scan-03',
          rawCode: differentCode,
          handshakeSecret: payload.handshakeSecret,
        ),
      );

      await transport.sendScan(diffMsg);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(receivedScans.length, 2);
      expect(receivedScans.last.rawCode, differentCode);
    });

    test('Replay attack re-using identical messageId is ignored', () async {
      final payload = await coordinator.startHosting(
        tenantId: tenantId,
        hostDeviceName: 'POS Counter 1',
      );

      await coordinator.joinAsScanner(
        payload: payload,
        deviceId: 'device-1',
        deviceName: 'Mobile 1',
      );

      final receivedScans = <WirelessScanMessage>[];
      coordinator.scans.listen((s) => receivedScans.add(s));

      final msg = WirelessScanMessage(
        messageId: 'replay-msg-id-123',
        sessionId: payload.sessionId,
        tenantId: tenantId,
        senderDeviceId: 'device-1',
        senderDeviceName: 'Mobile 1',
        rawCode: '8901234567890',
        format: SmartBarcodeFormat.ean13,
        timestamp: DateTime.now(),
        authSignature: WirelessScanMessage.computeSignature(
          sessionId: payload.sessionId,
          messageId: 'replay-msg-id-123',
          rawCode: '8901234567890',
          handshakeSecret: payload.handshakeSecret,
        ),
      );

      await transport.sendScan(msg);
      // Wait past duplicate suppression window so dedupe by code alone would allow it
      await Future<void>.delayed(const Duration(milliseconds: 550));

      // Replay identical messageId
      transport.simulateIncomingScan(msg);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Still only 1 scan delivered
      expect(receivedScans.length, 1);
    });

    test('Desktop acknowledges scan and mobile receives ack with product name', () async {
      final payload = await coordinator.startHosting(
        tenantId: tenantId,
        hostDeviceName: 'POS Counter 1',
      );

      await coordinator.joinAsScanner(
        payload: payload,
        deviceId: 'device-1',
        deviceName: 'Mobile 1',
      );

      final acks = <WirelessScanAck>[];
      transport.incomingAcks.listen((a) => acks.add(a));

      await coordinator.acknowledgeScan(
        messageId: 'scan-100',
        success: true,
        productName: 'Tata Steel TMT 12mm',
        quantity: 2.0,
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(acks.length, 1);
      expect(acks.first.messageId, 'scan-100');
      expect(acks.first.success, isTrue);
      expect(acks.first.productName, 'Tata Steel TMT 12mm');
      expect(acks.first.updatedQuantity, 2.0);
    });

    test('Unpair cleanly revokes session and resets state', () async {
      final payload = await coordinator.startHosting(
        tenantId: tenantId,
        hostDeviceName: 'POS Counter 1',
      );

      await coordinator.joinAsScanner(
        payload: payload,
        deviceId: 'device-1',
        deviceName: 'Mobile 1',
      );

      expect(coordinator.isConnected, isTrue);

      await coordinator.unpair();

      expect(coordinator.isConnected, isFalse);
      expect(coordinator.currentState, WirelessScannerState.disconnected);
      expect(coordinator.activeDevice, isNull);
    });
  });
}
