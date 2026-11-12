import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'scanner_models.dart';

/// Connection and pairing state of the wireless smart scanner system.
enum WirelessScannerState {
  /// Neither hosting nor connected to a remote scanner.
  disconnected,

  /// Desktop is hosting a pairing session and awaiting phone scan.
  pairingPending,

  /// Phone and desktop are actively paired and communicating.
  connected,

  /// Interrupted connection; attempting automatic reconnection.
  reconnecting,

  /// Pairing session explicitly revoked or terminated.
  revoked,

  /// Technical communication failure.
  error;

  String get label => switch (this) {
    WirelessScannerState.disconnected => 'Disconnected',
    WirelessScannerState.pairingPending => 'Awaiting Phone Pairing',
    WirelessScannerState.connected => 'Paired & Active',
    WirelessScannerState.reconnecting => 'Reconnecting...',
    WirelessScannerState.revoked => 'Pairing Revoked',
    WirelessScannerState.error => 'Connection Error',
  };
}

/// Delivery status of a scan transmitted from the mobile camera.
enum WirelessScanDeliveryStatus {
  pending,
  delivered,
  failed;

  String get label => switch (this) {
    WirelessScanDeliveryStatus.pending => 'Pending Transmission',
    WirelessScanDeliveryStatus.delivered => 'Delivered to Desktop',
    WirelessScanDeliveryStatus.failed => 'Delivery Failed',
  };
}

/// Short-lived pairing payload encoded into the desktop pairing QR code.
///
/// Security properties:
/// 1. Short-lived session credentials — strictly expires (default 10 minutes).
/// 2. Tenant isolation — strictly bound to `tenantId`. A phone belonging to another business cannot pair.
/// 3. Zero permanent credentials — contains no Supabase service-role keys, database passwords, or persistent API tokens.
/// 4. Cryptographic handshake secret — 128-bit random token used to HMAC-sign all subsequent scan packets.
class WirelessScannerPairingPayload {
  /// Protocol version.
  final int version;

  /// Unique UUID v4 identifying this specific pairing session.
  final String sessionId;

  /// Tenant business UUID for strict cross-tenant isolation.
  final String tenantId;

  /// Optional store or warehouse location UUID.
  final String? locationId;

  /// Human-friendly name of the desktop host (e.g. "POS Terminal 1 (Main Store)").
  final String hostDeviceName;

  /// Cryptographically random handshake secret for packet signing.
  final String handshakeSecret;

  /// Supabase Realtime channel name (`thq:scan:<tenantId>:<sessionId>`).
  final String channelName;

  /// When this pairing token was generated.
  final DateTime createdAt;

  /// Strict wall-clock expiration timestamp.
  final DateTime expiresAt;

  const WirelessScannerPairingPayload({
    this.version = 1,
    required this.sessionId,
    required this.tenantId,
    this.locationId,
    required this.hostDeviceName,
    required this.handshakeSecret,
    required this.channelName,
    required this.createdAt,
    required this.expiresAt,
  });

  /// Whether this pairing session has surpassed its expiration deadline.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Remaining duration before this pairing token expires.
  Duration get remainingDuration {
    final diff = expiresAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Encodes the payload into a compact, standardized JSON string for QR representation.
  String toQrString() {
    return jsonEncode({
      'type': 'thq_wireless_pair',
      'v': version,
      'sid': sessionId,
      'tid': tenantId,
      if (locationId != null) 'lid': locationId,
      'host': hostDeviceName,
      'sec': handshakeSecret,
      'chan': channelName,
      'cat': createdAt.toIso8601String(),
      'exp': expiresAt.toIso8601String(),
    });
  }

  /// Decodes and validates a QR code string.
  ///
  /// Throws [FormatException] if the QR code is malformed, unrecognized, or expired.
  factory WirelessScannerPairingPayload.fromQrString(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty QR code payload');
    }

    try {
      final map = jsonDecode(trimmed) as Map<String, dynamic>;
      if (map['type'] != 'thq_wireless_pair') {
        throw const FormatException('Not a valid THQ Wireless Scanner pairing QR code');
      }

      final v = (map['v'] as num?)?.toInt() ?? 1;
      final sid = map['sid']?.toString() ?? '';
      final tid = map['tid']?.toString() ?? '';
      final lid = map['lid']?.toString();
      final host = map['host']?.toString() ?? 'Desktop';
      final sec = map['sec']?.toString() ?? '';
      final chan = map['chan']?.toString() ?? '';
      final cat = DateTime.tryParse(map['cat']?.toString() ?? '') ?? DateTime.now();
      final exp = DateTime.tryParse(map['exp']?.toString() ?? '') ?? DateTime.now();

      if (sid.isEmpty || tid.isEmpty || sec.isEmpty || chan.isEmpty) {
        throw const FormatException('Pairing QR is missing mandatory cryptographic fields');
      }

      final payload = WirelessScannerPairingPayload(
        version: v,
        sessionId: sid,
        tenantId: tid,
        locationId: lid,
        hostDeviceName: host,
        handshakeSecret: sec,
        channelName: chan,
        createdAt: cat,
        expiresAt: exp,
      );

      if (payload.isExpired) {
        throw FormatException(
          'Pairing session expired at ${payload.expiresAt.toIso8601String()}. Please generate a fresh QR code on desktop.',
        );
      }

      return payload;
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Failed to parse pairing QR: $e');
    }
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'sessionId': sessionId,
        'tenantId': tenantId,
        'locationId': locationId,
        'hostDeviceName': hostDeviceName,
        'handshakeSecret': handshakeSecret,
        'channelName': channelName,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
      };
}

/// Barcode packet transmitted from the paired mobile phone to the desktop application.
class WirelessScanMessage {
  /// Unique UUID v4 identifying this scan message for deduplication and acknowledgement.
  final String messageId;

  /// Associated pairing session ID.
  final String sessionId;

  /// Tenant business ID to prevent cross-tenant message bleeding.
  final String tenantId;

  /// Device hardware/client identifier of the transmitting mobile device.
  final String senderDeviceId;

  /// Human-friendly model or device name (e.g. "Google Pixel 7 Pro").
  final String senderDeviceName;

  /// The exact decoded barcode string. Strict string preservation ensures leading zeros are not lost.
  final String rawCode;

  /// Standardized barcode symbology.
  final SmartBarcodeFormat format;

  /// Timestamp when the barcode was decoded by the camera.
  final DateTime timestamp;

  /// Cryptographic HMAC-SHA256 signature proving the sender possesses the `handshakeSecret`.
  final String authSignature;

  const WirelessScanMessage({
    required this.messageId,
    required this.sessionId,
    required this.tenantId,
    required this.senderDeviceId,
    required this.senderDeviceName,
    required this.rawCode,
    required this.format,
    required this.timestamp,
    required this.authSignature,
  });

  /// Factory constructor to generate message with a new ID and computed HMAC signature.
  factory WirelessScanMessage.create({
    required String sessionId,
    required String tenantId,
    required String senderDeviceId,
    required String senderDeviceName,
    required String rawCode,
    required SmartBarcodeFormat format,
    required String handshakeSecret,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();
    final mid = 'msg-${now.microsecondsSinceEpoch}';
    final sig = computeSignature(
      sessionId: sessionId,
      messageId: mid,
      rawCode: rawCode,
      handshakeSecret: handshakeSecret,
    );
    return WirelessScanMessage(
      messageId: mid,
      sessionId: sessionId,
      tenantId: tenantId,
      senderDeviceId: senderDeviceId,
      senderDeviceName: senderDeviceName,
      rawCode: rawCode,
      format: format,
      timestamp: now,
      authSignature: sig,
    );
  }

  /// Computes the HMAC-SHA256 signature for a scan message payload.
  static String computeSignature({
    required String sessionId,
    required String messageId,
    required String rawCode,
    required String handshakeSecret,
  }) {
    final hmac = Hmac(sha256, utf8.encode(handshakeSecret));
    final digest = hmac.convert(utf8.encode('$sessionId:$messageId:$rawCode'));
    return digest.toString();
  }

  /// Verifies whether this message was signed with the expected handshake secret.
  bool verifySignature(String handshakeSecret) {
    final expected = computeSignature(
      sessionId: sessionId,
      messageId: messageId,
      rawCode: rawCode,
      handshakeSecret: handshakeSecret,
    );
    return expected == authSignature;
  }

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'sessionId': sessionId,
        'tenantId': tenantId,
        'senderDeviceId': senderDeviceId,
        'senderDeviceName': senderDeviceName,
        'rawCode': rawCode,
        'format': format.name,
        'timestamp': timestamp.toIso8601String(),
        'authSignature': authSignature,
      };

  factory WirelessScanMessage.fromJson(Map<String, dynamic> map) {
    return WirelessScanMessage(
      messageId: map['messageId']?.toString() ?? '',
      sessionId: map['sessionId']?.toString() ?? '',
      tenantId: map['tenantId']?.toString() ?? '',
      senderDeviceId: map['senderDeviceId']?.toString() ?? '',
      senderDeviceName: map['senderDeviceName']?.toString() ?? 'Mobile Scanner',
      rawCode: map['rawCode']?.toString() ?? '',
      format: SmartBarcodeFormat.fromRawName(map['format']?.toString() ?? ''),
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
      authSignature: map['authSignature']?.toString() ?? '',
    );
  }
}

/// Confirmation packet broadcast by the desktop to the phone upon receiving a scan.
class WirelessScanAck {
  /// The corresponding `messageId` that was received.
  final String messageId;

  /// Session ID under which the scan was delivered.
  final String sessionId;

  /// Whether the scan was successfully processed into the active workflow.
  final bool success;

  /// Optional product name resolved on the desktop (e.g. "UltraTech Cement 50kg").
  final String? productName;

  /// Optional variant name resolved on desktop.
  final String? variantName;

  /// Updated quantity in the active cart or count line.
  final double? updatedQuantity;

  /// Optional error or warning message (e.g. "Product out of stock").
  final String? errorMessage;

  /// Timestamp when the desktop acknowledged receipt.
  final DateTime timestamp;

  const WirelessScanAck({
    required this.messageId,
    required this.sessionId,
    required this.success,
    this.productName,
    this.variantName,
    this.updatedQuantity,
    this.errorMessage,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'sessionId': sessionId,
        'success': success,
        if (productName != null) 'productName': productName,
        if (variantName != null) 'variantName': variantName,
        if (updatedQuantity != null) 'updatedQuantity': updatedQuantity,
        if (errorMessage != null) 'errorMessage': errorMessage,
        'timestamp': timestamp.toIso8601String(),
      };

  factory WirelessScanAck.fromJson(Map<String, dynamic> map) {
    return WirelessScanAck(
      messageId: map['messageId']?.toString() ?? '',
      sessionId: map['sessionId']?.toString() ?? '',
      success: map['success'] == true,
      productName: map['productName']?.toString(),
      variantName: map['variantName']?.toString(),
      updatedQuantity: (map['updatedQuantity'] as num?)?.toDouble(),
      errorMessage: map['errorMessage']?.toString(),
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// Metadata describing a mobile device paired with the desktop host.
class WirelessScannerDevice {
  final String deviceId;
  final String deviceName;
  final DateTime pairedAt;
  DateTime lastSeenAt;
  int scansSent;

  WirelessScannerDevice({
    required this.deviceId,
    required this.deviceName,
    required this.pairedAt,
    required this.lastSeenAt,
    this.scansSent = 0,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'pairedAt': pairedAt.toIso8601String(),
        'lastSeenAt': lastSeenAt.toIso8601String(),
        'scansSent': scansSent,
      };
}

/// In-memory scan entry stored in the mobile session history drawer.
class WirelessScanHistoryItem {
  final String messageId;
  final String rawCode;
  final SmartBarcodeFormat format;
  final DateTime timestamp;
  WirelessScanDeliveryStatus status;
  String? productName;
  String? errorMessage;
  WirelessScanAck? ack;

  WirelessScanHistoryItem({
    required this.messageId,
    required this.rawCode,
    required this.format,
    required this.timestamp,
    this.status = WirelessScanDeliveryStatus.pending,
    this.productName,
    this.errorMessage,
    this.ack,
  });
}
