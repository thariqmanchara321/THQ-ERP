import 'package:flutter/foundation.dart';

/// Supported operational modes for the smart scanner.
enum ScannerMode {
  /// Stops processing after the first accepted scan until resumed or restarted.
  single,

  /// Continues processing scans, applying duplicate suppression rules.
  continuous,
}

/// The physical or logical origin of the scanned input.
enum ScannerSource {
  camera,
  usb,
  bluetooth,
  manual,
  qr,
  remotePhone,
}

/// Lifecycle status of the scanner controller.
enum ScannerStatus {
  idle,
  ready,
  scanning,
  paused,
  stopped,
  error,
}

/// Standardized barcode symbologies recognized across THQ ERP.
enum SmartBarcodeFormat {
  ean8,
  ean13,
  upcA,
  upcE,
  code128,
  code39,
  code93,
  itf,
  qrCode,
  dataMatrix,
  unknown;

  /// Returns a human-friendly display label.
  String get displayName => label;

  /// Returns a human-friendly display label.
  String get label => switch (this) {
    SmartBarcodeFormat.ean8 => 'EAN-8',
    SmartBarcodeFormat.ean13 => 'EAN-13',
    SmartBarcodeFormat.upcA => 'UPC-A',
    SmartBarcodeFormat.upcE => 'UPC-E',
    SmartBarcodeFormat.code128 => 'Code 128',
    SmartBarcodeFormat.code39 => 'Code 39',
    SmartBarcodeFormat.code93 => 'Code 93',
    SmartBarcodeFormat.itf => 'ITF',
    SmartBarcodeFormat.qrCode => 'QR Code',
    SmartBarcodeFormat.dataMatrix => 'Data Matrix',
    SmartBarcodeFormat.unknown => 'Barcode / QR',
  };

  /// Parses common raw format names from camera or hardware scanners.
  static SmartBarcodeFormat fromRawName(String? raw) {
    if (raw == null) return SmartBarcodeFormat.unknown;
    final normalized = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return switch (normalized) {
      'ean8' => SmartBarcodeFormat.ean8,
      'ean13' => SmartBarcodeFormat.ean13,
      'upca' => SmartBarcodeFormat.upcA,
      'upce' => SmartBarcodeFormat.upcE,
      'code128' => SmartBarcodeFormat.code128,
      'code39' => SmartBarcodeFormat.code39,
      'code93' => SmartBarcodeFormat.code93,
      'itf' => SmartBarcodeFormat.itf,
      'qrcode' || 'qr' => SmartBarcodeFormat.qrCode,
      'datamatrix' => SmartBarcodeFormat.dataMatrix,
      _ => SmartBarcodeFormat.unknown,
    };
  }
}

/// An immutable scan event produced by any THQ scanner input.
@immutable
class SmartScanResult {
  /// The unaltered scanned string emitted by the sensor/keyboard wedge.
  final String rawValue;

  /// The normalized string (trimmed, non-printable characters removed, leading zeros preserved).
  final String normalizedValue;

  /// Symbology detected.
  final SmartBarcodeFormat format;

  /// Physical or logical source.
  final ScannerSource source;

  /// Timestamp of detection.
  final DateTime timestamp;

  /// Optional active session correlation ID (e.g. stock count or bulk scan).
  final String? sessionId;

  /// Optional hardware or device identifier.
  final String? deviceId;

  /// Whether the raw value passed scanner-level validation.
  final bool isValid;

  /// Optional error or diagnostic message if invalid.
  final String? errorMessage;

  const SmartScanResult({
    required this.rawValue,
    required this.normalizedValue,
    required this.format,
    required this.source,
    required this.timestamp,
    this.sessionId,
    this.deviceId,
    this.isValid = true,
    this.errorMessage,
  });

  /// Factory constructing a valid scan result, computing the normalized value while preserving leading zeros.
  factory SmartScanResult.valid({
    required String rawValue,
    SmartBarcodeFormat format = SmartBarcodeFormat.unknown,
    ScannerSource source = ScannerSource.manual,
    DateTime? timestamp,
    String? sessionId,
    String? deviceId,
  }) {
    final cleaned = rawValue.trim();
    return SmartScanResult(
      rawValue: rawValue,
      normalizedValue: cleaned,
      format: format,
      source: source,
      timestamp: timestamp ?? DateTime.now().toUtc(),
      sessionId: sessionId,
      deviceId: deviceId,
      isValid: true,
      errorMessage: null,
    );
  }

  /// Factory constructing an invalid/rejected scan result.
  factory SmartScanResult.invalid({
    required String rawValue,
    required String errorMessage,
    SmartBarcodeFormat format = SmartBarcodeFormat.unknown,
    ScannerSource source = ScannerSource.manual,
    DateTime? timestamp,
    String? sessionId,
    String? deviceId,
  }) {
    return SmartScanResult(
      rawValue: rawValue,
      normalizedValue: rawValue.trim(),
      format: format,
      source: source,
      timestamp: timestamp ?? DateTime.now().toUtc(),
      sessionId: sessionId,
      deviceId: deviceId,
      isValid: false,
      errorMessage: errorMessage,
    );
  }

  SmartScanResult copyWith({
    String? rawValue,
    String? normalizedValue,
    SmartBarcodeFormat? format,
    ScannerSource? source,
    DateTime? timestamp,
    String? sessionId,
    String? deviceId,
    bool? isValid,
    String? errorMessage,
  }) {
    return SmartScanResult(
      rawValue: rawValue ?? this.rawValue,
      normalizedValue: normalizedValue ?? this.normalizedValue,
      format: format ?? this.format,
      source: source ?? this.source,
      timestamp: timestamp ?? this.timestamp,
      sessionId: sessionId ?? this.sessionId,
      deviceId: deviceId ?? this.deviceId,
      isValid: isValid ?? this.isValid,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toMap() => {
    'raw_value': rawValue,
    'normalized_value': normalizedValue,
    'format': format.name,
    'source': source.name,
    'timestamp': timestamp.toIso8601String(),
    if (sessionId != null) 'session_id': sessionId,
    if (deviceId != null) 'device_id': deviceId,
    'is_valid': isValid,
    if (errorMessage != null) 'error_message': errorMessage,
  };

  factory SmartScanResult.fromMap(Map<String, dynamic> map) {
    return SmartScanResult(
      rawValue: map['raw_value']?.toString() ?? '',
      normalizedValue: map['normalized_value']?.toString() ?? '',
      format: SmartBarcodeFormat.fromRawName(map['format']?.toString()),
      source: ScannerSource.values.firstWhere(
        (e) => e.name == map['source']?.toString(),
        orElse: () => ScannerSource.manual,
      ),
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
      sessionId: map['session_id']?.toString(),
      deviceId: map['device_id']?.toString(),
      isValid: map['is_valid'] != false,
      errorMessage: map['error_message']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmartScanResult &&
          runtimeType == other.runtimeType &&
          rawValue == other.rawValue &&
          normalizedValue == other.normalizedValue &&
          format == other.format &&
          source == other.source &&
          timestamp == other.timestamp &&
          sessionId == other.sessionId &&
          deviceId == other.deviceId &&
          isValid == other.isValid &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
    rawValue,
    normalizedValue,
    format,
    source,
    timestamp,
    sessionId,
    deviceId,
    isValid,
    errorMessage,
  );

  @override
  String toString() =>
      'SmartScanResult(code: "$normalizedValue", format: ${format.name}, source: ${source.name}, valid: $isValid)';
}

/// Configuration tuning scanner behavior.
@immutable
class ScannerConfiguration {
  /// Operational mode: single vs continuous.
  final ScannerMode mode;

  /// Duration to suppress identical consecutive scans of the same code.
  final Duration duplicateSuppressionDuration;

  /// When true, identical scans are immediately accepted regardless of suppression duration.
  final bool allowDuplicates;

  /// Automatically stop/pause scanning after the first valid scan event.
  final bool stopOnFirstResult;

  /// Minimum acceptable character length.
  final int minInputLength;

  /// Maximum acceptable character length.
  final int maxInputLength;

  /// Maximum in-memory scan history buffer size.
  final int maxHistorySize;

  /// Optional active session ID.
  final String? sessionId;

  /// Optional hardware device identifier.
  final String? deviceId;

  const ScannerConfiguration({
    this.mode = ScannerMode.continuous,
    this.duplicateSuppressionDuration = const Duration(milliseconds: 1200),
    this.allowDuplicates = false,
    this.stopOnFirstResult = false,
    this.minInputLength = 1,
    this.maxInputLength = 128,
    this.maxHistorySize = 100,
    this.sessionId,
    this.deviceId,
  });

  /// Default configuration for point-of-sale rapid barcode checkout.
  factory ScannerConfiguration.pos({String? deviceId, String? sessionId}) => ScannerConfiguration(
    mode: ScannerMode.continuous,
    duplicateSuppressionDuration: const Duration(milliseconds: 800),
    allowDuplicates: false,
    stopOnFirstResult: false,
    minInputLength: 1,
    maxInputLength: 128,
    maxHistorySize: 150,
    sessionId: sessionId,
    deviceId: deviceId,
  );

  /// Default configuration for modal/dialog single barcode lookup.
  factory ScannerConfiguration.single({String? deviceId}) => ScannerConfiguration(
    mode: ScannerMode.single,
    duplicateSuppressionDuration: const Duration(milliseconds: 1000),
    allowDuplicates: false,
    stopOnFirstResult: true,
    minInputLength: 1,
    maxInputLength: 128,
    maxHistorySize: 20,
    deviceId: deviceId,
  );

  /// Default configuration for stock counting and physical inventory audit.
  factory ScannerConfiguration.stockCount({String? sessionId, String? deviceId}) => ScannerConfiguration(
    mode: ScannerMode.continuous,
    duplicateSuppressionDuration: const Duration(milliseconds: 600),
    allowDuplicates: false,
    stopOnFirstResult: false,
    minInputLength: 1,
    maxInputLength: 128,
    maxHistorySize: 500,
    sessionId: sessionId,
    deviceId: deviceId,
  );

  ScannerConfiguration copyWith({
    ScannerMode? mode,
    Duration? duplicateSuppressionDuration,
    bool? allowDuplicates,
    bool? stopOnFirstResult,
    int? minInputLength,
    int? maxInputLength,
    int? maxHistorySize,
    String? sessionId,
    String? deviceId,
  }) {
    return ScannerConfiguration(
      mode: mode ?? this.mode,
      duplicateSuppressionDuration:
          duplicateSuppressionDuration ?? this.duplicateSuppressionDuration,
      allowDuplicates: allowDuplicates ?? this.allowDuplicates,
      stopOnFirstResult: stopOnFirstResult ?? this.stopOnFirstResult,
      minInputLength: minInputLength ?? this.minInputLength,
      maxInputLength: maxInputLength ?? this.maxInputLength,
      maxHistorySize: maxHistorySize ?? this.maxHistorySize,
      sessionId: sessionId ?? this.sessionId,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScannerConfiguration &&
          runtimeType == other.runtimeType &&
          mode == other.mode &&
          duplicateSuppressionDuration == other.duplicateSuppressionDuration &&
          allowDuplicates == other.allowDuplicates &&
          stopOnFirstResult == other.stopOnFirstResult &&
          minInputLength == other.minInputLength &&
          maxInputLength == other.maxInputLength &&
          maxHistorySize == other.maxHistorySize &&
          sessionId == other.sessionId &&
          deviceId == other.deviceId;

  @override
  int get hashCode => Object.hash(
    mode,
    duplicateSuppressionDuration,
    allowDuplicates,
    stopOnFirstResult,
    minInputLength,
    maxInputLength,
    maxHistorySize,
    sessionId,
    deviceId,
  );
}
