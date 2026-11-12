import 'dart:async';

import 'wireless_scanner_models.dart';
import 'wireless_scanner_transport.dart';

/// Central coordinator managing wireless smart scanner pairing, duplicate suppression,
/// cryptographic signature verification, and barcode dispatch to desktop workflows.
class WirelessScannerCoordinator {
  WirelessScannerTransport transport;
  final Duration duplicateSuppressionDuration;

  StreamSubscription<WirelessScanMessage>? _scanSub;
  StreamSubscription<WirelessScannerState>? _stateSub;
  StreamSubscription<WirelessScannerDevice?>? _deviceSub;

  final StreamController<WirelessScanMessage> _verifiedScans =
      StreamController<WirelessScanMessage>.broadcast();
  final StreamController<WirelessScannerState> _stateController =
      StreamController<WirelessScannerState>.broadcast();
  final StreamController<WirelessScannerDevice?> _deviceController =
      StreamController<WirelessScannerDevice?>.broadcast();

  // Deduplication & Replay Prevention
  final Map<String, DateTime> _recentScans = {};
  final Set<String> _seenMessageIds = {};
  final Map<String, String> _recentScanCodesByMessageId = {};
  Timer? _dedupeCleanupTimer;
  Timer? _expirationTimer;

  WirelessScannerCoordinator({
    required this.transport,
    this.duplicateSuppressionDuration = const Duration(milliseconds: 900),
  }) {
    _initSubscriptions();
    _startDedupeCleanup();
  }

  void _initSubscriptions() {
    _scanSub = transport.incomingScans.listen(_handleIncomingScan);
    _stateSub = transport.stateStream.listen((s) => _stateController.add(s));
    _deviceSub = transport.pairedDeviceStream.listen((d) => _deviceController.add(d));
  }

  void _startDedupeCleanup() {
    _dedupeCleanupTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 60));
      _recentScans.removeWhere((_, time) => time.isBefore(cutoff));
      if (_seenMessageIds.length > 500) {
        _seenMessageIds.clear();
        _recentScanCodesByMessageId.clear();
      }
    });
  }

  /// Sets a custom or mock transport (useful for testing or switching between transports).
  void setTransport(WirelessScannerTransport newTransport) {
    _scanSub?.cancel();
    _stateSub?.cancel();
    _deviceSub?.cancel();

    transport = newTransport;
    _initSubscriptions();
  }

  /// Stream of validated, deduplicated scans ready for consumption by POS or Smart Inventory.
  Stream<WirelessScanMessage> get scans => _verifiedScans.stream;

  /// Current connection state.
  WirelessScannerState get state => transport.currentState;

  /// Current state.
  WirelessScannerState get currentState => transport.currentState;

  /// Stream of connection states.
  Stream<WirelessScannerState> get stateStream => _stateController.stream;

  /// Stream of paired mobile device metadata.
  Stream<WirelessScannerDevice?> get deviceStream => _deviceController.stream;
  Stream<WirelessScannerDevice?> get pairedDevice => _deviceController.stream;

  /// Active paired device, if any.
  WirelessScannerDevice? get activeDevice => transport.activeDevice;

  /// Current pairing payload.
  WirelessScannerPairingPayload? get currentPayload => transport.currentPayload;

  /// Whether a phone is actively paired and connected.
  bool get isConnected => transport.currentState == WirelessScannerState.connected;

  /// Starts hosting on desktop and begins session expiration timer.
  Future<WirelessScannerPairingPayload> startHostingSession({
    required String tenantId,
    String? locationId,
    required String hostDeviceName,
    Duration expiration = const Duration(minutes: 10),
  }) =>
      startHosting(
        tenantId: tenantId,
        locationId: locationId,
        hostDeviceName: hostDeviceName,
        expiration: expiration,
      );

  /// Starts hosting on desktop and begins session expiration timer.
  Future<WirelessScannerPairingPayload> startHosting({
    required String tenantId,
    String? locationId,
    required String hostDeviceName,
    Duration expiration = const Duration(minutes: 10),
  }) async {
    _expirationTimer?.cancel();
    _recentScans.clear();
    _seenMessageIds.clear();
    _recentScanCodesByMessageId.clear();

    final payload = await transport.startHosting(
      tenantId: tenantId,
      locationId: locationId,
      hostDeviceName: hostDeviceName,
      expiration: expiration,
    );

    _expirationTimer = Timer(expiration, () {
      if (!isConnected) {
        unpair();
      }
    });

    return payload;
  }

  /// Connects from mobile phone to desktop host.
  Future<bool> joinAsScanner({
    required WirelessScannerPairingPayload payload,
    required String deviceId,
    required String deviceName,
    String? currentTenantId,
    String? currentLocationId,
  }) async {
    if (payload.isExpired || payload.isConsumed || payload.isRevoked) {
      return false;
    }
    if (currentTenantId != null &&
        currentTenantId.isNotEmpty &&
        payload.tenantId.isNotEmpty &&
        currentTenantId != payload.tenantId) {
      return false;
    }
    if (currentLocationId != null &&
        currentLocationId.isNotEmpty &&
        payload.locationId != null &&
        payload.locationId!.isNotEmpty &&
        currentLocationId != payload.locationId) {
      return false;
    }

    return transport.joinAsScanner(
      payload: payload,
      deviceId: deviceId,
      deviceName: deviceName,
      currentTenantId: currentTenantId,
      currentLocationId: currentLocationId,
    );
  }

  void _handleIncomingScan(WirelessScanMessage scan) {
    // 0. Freshness Check: reject scans older than 30 seconds
    if (!scan.isFresh) {
      return;
    }

    // 1. Replay Prevention: reject if messageId was already processed
    if (_seenMessageIds.contains(scan.messageId)) {
      return;
    }
    _seenMessageIds.add(scan.messageId);
    _recentScanCodesByMessageId[scan.messageId] = scan.rawCode;

    // 2. Duplicate Suppression: reject rapid identical scans within suppression window
    final now = DateTime.now();
    final lastTime = _recentScans[scan.rawCode];
    if (lastTime != null && now.difference(lastTime) < duplicateSuppressionDuration) {
      // Explicit duplicate ACK to mobile so user sees instant feedback
      acknowledgeScan(
        messageId: scan.messageId,
        receivedCode: scan.rawCode,
        success: true,
        isDuplicate: true,
        productName: 'Duplicate scan suppressed',
      );
      return;
    }
    _recentScans[scan.rawCode] = now;

    // 3. Dispatch to listeners
    _verifiedScans.add(scan);
  }

  /// Sends receipt acknowledgement with optional product name back to the phone.
  Future<void> acknowledgeScan({
    required String messageId,
    required bool success,
    String? receivedCode,
    bool isDuplicate = false,
    String? productName,
    String? variantName,
    double? quantity,
    String? errorMessage,
  }) async {
    final payload = transport.currentPayload;
    if (payload == null) return;

    final code = receivedCode ?? _recentScanCodesByMessageId[messageId] ?? '';

    final ack = WirelessScanAck.create(
      messageId: messageId,
      sessionId: payload.sessionId,
      success: success,
      receivedCode: code,
      handshakeSecret: payload.handshakeSecret,
      isDuplicate: isDuplicate,
      productName: productName,
      variantName: variantName,
      updatedQuantity: quantity,
      errorMessage: errorMessage,
      timestamp: DateTime.now(),
    );

    await transport.sendAck(ack);
  }

  /// Unpairs the active device and resets the coordinator state.
  Future<void> unpair() async {
    _expirationTimer?.cancel();
    await transport.unpair();
  }

  void dispose() {
    _expirationTimer?.cancel();
    _dedupeCleanupTimer?.cancel();
    _scanSub?.cancel();
    _stateSub?.cancel();
    _deviceSub?.cancel();
    _verifiedScans.close();
    _stateController.close();
    _deviceController.close();
    transport.dispose();
  }
}
