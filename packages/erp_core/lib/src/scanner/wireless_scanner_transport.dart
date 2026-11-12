import 'wireless_scanner_models.dart';

/// Pluggable transport contract enabling wireless communication between
/// desktop host applications and mobile camera barcode scanners.
abstract class WirelessScannerTransport {
  /// Stream of validated barcode scans received from a paired mobile device.
  Stream<WirelessScanMessage> get incomingScans;

  /// Stream of delivery confirmations received from the desktop host.
  Stream<WirelessScanAck> get incomingAcks;

  /// Stream of currently paired mobile device metadata (null if disconnected).
  Stream<WirelessScannerDevice?> get pairedDeviceStream;

  /// Stream of wireless connection lifecycle states.
  Stream<WirelessScannerState> get stateStream;

  /// Current connection state.
  WirelessScannerState get currentState;

  /// Metadata for the active paired mobile device, if connected.
  WirelessScannerDevice? get activeDevice;

  /// Current active pairing payload, if hosting or joined.
  WirelessScannerPairingPayload? get currentPayload;

  /// Initializes a desktop hosting session, generating a short-lived pairing payload.
  Future<WirelessScannerPairingPayload> startHosting({
    required String tenantId,
    String? locationId,
    required String hostDeviceName,
    Duration expiration = const Duration(minutes: 10),
  });

  /// Connects from a mobile device to an existing desktop hosting session.
  Future<bool> joinAsScanner({
    required WirelessScannerPairingPayload payload,
    required String deviceId,
    required String deviceName,
  });

  /// Transmits a scanned barcode from mobile to the paired desktop host.
  Future<bool> sendScan(WirelessScanMessage scan);

  /// Sends a scan reception acknowledgement from desktop back to mobile.
  Future<void> sendAck(WirelessScanAck ack);

  /// Explicitly unpairs and closes the active wireless session.
  Future<void> unpair();

  /// Releases resources and closes open streams.
  void dispose();
}
