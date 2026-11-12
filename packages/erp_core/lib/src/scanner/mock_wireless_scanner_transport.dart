import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'wireless_scanner_models.dart';
import 'wireless_scanner_transport.dart';

/// In-memory mock implementation of [WirelessScannerTransport] for hermetic,
/// lightning-fast, and deterministic unit and widget testing.
class MockWirelessScannerTransport implements WirelessScannerTransport {
  final StreamController<WirelessScanMessage> _scanController =
      StreamController<WirelessScanMessage>.broadcast();
  final StreamController<WirelessScanAck> _ackController =
      StreamController<WirelessScanAck>.broadcast();
  final StreamController<WirelessScannerDevice?> _deviceController =
      StreamController<WirelessScannerDevice?>.broadcast();
  final StreamController<WirelessScannerState> _stateController =
      StreamController<WirelessScannerState>.broadcast();

  WirelessScannerState _state = WirelessScannerState.disconnected;
  WirelessScannerDevice? _device;
  WirelessScannerPairingPayload? _payload;
  bool _isDisposed = false;

  /// Whether desktop mock should automatically reply with an acknowledgement for any received scan.
  bool autoAck = true;

  /// Optional product name to supply in auto-acknowledgements.
  String autoAckProductName = 'Identified Test Product';

  /// Whether simulated network sends should intentionally fail (simulate offline).
  bool simulateNetworkFailure = false;

  @override
  Stream<WirelessScanMessage> get incomingScans => _scanController.stream;

  @override
  Stream<WirelessScanAck> get incomingAcks => _ackController.stream;

  @override
  Stream<WirelessScannerDevice?> get pairedDeviceStream => _deviceController.stream;

  @override
  Stream<WirelessScannerState> get stateStream => _stateController.stream;

  @override
  WirelessScannerState get currentState => _state;

  @override
  WirelessScannerDevice? get activeDevice => _device;

  @override
  WirelessScannerPairingPayload? get currentPayload => _payload;

  void _setState(WirelessScannerState newState) {
    _state = newState;
    if (!_isDisposed && !_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  @override
  Future<WirelessScannerPairingPayload> startHosting({
    required String tenantId,
    String? locationId,
    required String hostDeviceName,
    Duration expiration = const Duration(minutes: 10),
  }) async {
    final now = DateTime.now();
    final secureRandom = Random.secure();
    final randomBytes = List<int>.generate(32, (_) => secureRandom.nextInt(256));
    final secret = base64Url.encode(randomBytes);
    final sid = 'session-${now.microsecondsSinceEpoch}';

    _payload = WirelessScannerPairingPayload(
      version: 1,
      sessionId: sid,
      tenantId: tenantId,
      locationId: locationId,
      hostDeviceName: hostDeviceName,
      handshakeSecret: secret,
      channelName: 'thq:scan:$tenantId:$sid',
      createdAt: now,
      expiresAt: now.add(expiration),
    );

    _setState(WirelessScannerState.pairingPending);
    return _payload!;
  }

  /// Convenient alias for joining session in tests.
  Future<bool> joinSession({
    required WirelessScannerPairingPayload payload,
    required String phoneDeviceId,
    required String phoneDeviceName,
  }) =>
      joinAsScanner(
        payload: payload,
        deviceId: phoneDeviceId,
        deviceName: phoneDeviceName,
      );

  @override
  Future<bool> joinAsScanner({
    required WirelessScannerPairingPayload payload,
    required String deviceId,
    required String deviceName,
    String? currentTenantId,
    String? currentLocationId,
  }) async {
    if (payload.isExpired || payload.isConsumed || payload.isRevoked) {
      _setState(WirelessScannerState.error);
      return false;
    }
    if (currentTenantId != null &&
        currentTenantId.isNotEmpty &&
        payload.tenantId.isNotEmpty &&
        currentTenantId != payload.tenantId) {
      _setState(WirelessScannerState.error);
      return false;
    }
    if (currentLocationId != null &&
        currentLocationId.isNotEmpty &&
        payload.locationId != null &&
        payload.locationId!.isNotEmpty &&
        currentLocationId != payload.locationId) {
      _setState(WirelessScannerState.error);
      return false;
    }

    payload.consume();
    _payload = payload;
    _device = WirelessScannerDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      pairedAt: DateTime.now(),
      lastSeenAt: DateTime.now(),
    );

    _deviceController.add(_device);
    _setState(WirelessScannerState.connected);
    return true;
  }

  @override
  Future<bool> sendScan(WirelessScanMessage scan) async {
    if (simulateNetworkFailure) {
      return false;
    }

    if (_payload == null || _state != WirelessScannerState.connected) {
      return false;
    }

    if (!scan.isFresh) {
      return false;
    }

    if (scan.sessionId != _payload!.sessionId) {
      return false;
    }

    if (!scan.verifySignature(_payload!.handshakeSecret)) {
      return false;
    }

    _scanController.add(scan);
    _device?.lastSeenAt = DateTime.now();
    _device?.scansSent += 1;

    if (autoAck) {
      Timer(const Duration(milliseconds: 30), () {
        if (_isDisposed || _ackController.isClosed) return;
        final ack = WirelessScanAck.create(
          messageId: scan.messageId,
          sessionId: scan.sessionId,
          success: true,
          receivedCode: scan.rawCode,
          handshakeSecret: _payload!.handshakeSecret,
          productName: autoAckProductName,
          timestamp: DateTime.now(),
        );
        if (!_isDisposed && !_ackController.isClosed) {
          _ackController.add(ack);
        }
      });
    }

    return true;
  }

  @override
  Future<void> sendAck(WirelessScanAck ack) async {
    if (_isDisposed || _ackController.isClosed) return;
    _ackController.add(ack);
  }

  @override
  Future<void> unpair() async {
    _payload?.revoke();
    _setState(WirelessScannerState.revoked);
    _device = null;
    if (!_isDisposed && !_deviceController.isClosed) {
      _deviceController.add(null);
    }
    _payload = null;
    _setState(WirelessScannerState.disconnected);
  }

  /// Injects a scan into the incoming stream as if transmitted over the network.
  void simulateIncomingScan(WirelessScanMessage scan) {
    if (_isDisposed || _scanController.isClosed) return;
    _scanController.add(scan);
  }

  /// Injects an ACK into the incoming stream as if replied by desktop.
  void simulateIncomingAck(WirelessScanAck ack) {
    if (_isDisposed || _ackController.isClosed) return;
    _ackController.add(ack);
  }

  /// Simulates a temporary network disconnection.
  void simulateDisconnect() {
    _setState(WirelessScannerState.reconnecting);
  }

  /// Simulates reconnection after an interruption.
  void simulateReconnect() {
    _setState(WirelessScannerState.connected);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _scanController.close();
    _ackController.close();
    _deviceController.close();
    _stateController.close();
  }
}
