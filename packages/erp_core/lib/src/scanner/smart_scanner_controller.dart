import 'dart:async';
import 'dart:collection';

import 'scanner_models.dart';

/// Reusable controller managing barcode/QR scan state, validation, duplicate suppression,
/// and in-memory scan history independently of UI widgets and camera plugins.
class SmartScannerController {
  ScannerConfiguration _configuration;
  final DateTime Function() _now;

  ScannerStatus _status = ScannerStatus.idle;
  String? _lastErrorMessage;
  bool _isDisposed = false;

  final StreamController<SmartScanResult> _scansController =
      StreamController<SmartScanResult>.broadcast();
  final StreamController<ScannerStatus> _statusController =
      StreamController<ScannerStatus>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  final List<SmartScanResult> _history = [];
  final Map<String, DateTime> _recentScanTimestamps = HashMap<String, DateTime>();

  /// Creates a [SmartScannerController].
  ///
  /// An optional [clockSupplier] can be injected for deterministic time testing.
  SmartScannerController({
    ScannerConfiguration? configuration,
    DateTime Function()? clockSupplier,
  })  : _configuration = configuration ?? const ScannerConfiguration(),
        _now = clockSupplier ?? DateTime.now;

  /// Current operational status.
  ScannerStatus get status => _status;

  /// Current scanner configuration.
  ScannerConfiguration get configuration => _configuration;

  /// Unmodifiable view of accepted scan history (newest first).
  List<SmartScanResult> get history => UnmodifiableListView(_history);

  /// The most recently accepted scan result.
  SmartScanResult? get latestResult => _history.isEmpty ? null : _history.first;

  /// Most recent error message encountered, if any.
  String? get lastErrorMessage => _lastErrorMessage;

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Stream emitting accepted [SmartScanResult] events.
  Stream<SmartScanResult> get scans => _scansController.stream;

  /// Stream emitting scanner lifecycle changes.
  Stream<ScannerStatus> get statusStream => _statusController.stream;

  /// Stream emitting error messages.
  Stream<String> get errors => _errorController.stream;

  /// Starts the scanner and transitions to [ScannerStatus.scanning].
  void start() {
    _checkDisposed();
    if (_status == ScannerStatus.scanning) return;
    _updateStatus(ScannerStatus.scanning);
  }

  /// Stops scanner processing and marks it [ScannerStatus.stopped].
  void stop() {
    _checkDisposed();
    if (_status == ScannerStatus.stopped) return;
    _updateStatus(ScannerStatus.stopped);
  }

  /// Pauses scan processing without destroying recent state or history.
  void pause() {
    _checkDisposed();
    if (_status == ScannerStatus.paused || _status == ScannerStatus.stopped) return;
    _updateStatus(ScannerStatus.paused);
  }

  /// Resumes scan processing from a paused state.
  void resume() {
    _checkDisposed();
    if (_status == ScannerStatus.scanning) return;
    _updateStatus(ScannerStatus.scanning);
  }

  /// Resets controller state, clearing recent duplicate suppression timestamps while keeping configuration.
  void reset() {
    _checkDisposed();
    _recentScanTimestamps.clear();
    _lastErrorMessage = null;
    _updateStatus(ScannerStatus.ready);
  }

  /// Changes the operational mode (single vs continuous).
  void setMode(ScannerMode mode) {
    _checkDisposed();
    if (_configuration.mode == mode) return;
    _configuration = _configuration.copyWith(
      mode: mode,
      stopOnFirstResult: mode == ScannerMode.single,
    );
  }

  /// Updates configuration immutably via a transformer callback.
  void updateConfiguration(ScannerConfiguration Function(ScannerConfiguration) update) {
    _checkDisposed();
    _configuration = update(_configuration);
    _trimHistory();
  }

  /// Submits a raw scanned string for validation, deduplication, and emission.
  ///
  /// Returns the accepted [SmartScanResult], or `null` if the scan was suppressed,
  /// rejected by validation, or submitted while the scanner was paused/stopped.
  SmartScanResult? submitScan(
    String rawValue, {
    SmartBarcodeFormat format = SmartBarcodeFormat.unknown,
    ScannerSource source = ScannerSource.manual,
    String? deviceId,
    String? sessionId,
  }) {
    _checkDisposed();

    // Ignore incoming scans if paused or stopped
    if (_status == ScannerStatus.paused || _status == ScannerStatus.stopped) {
      return null;
    }

    final normalized = rawValue.trim();

    // 1. Scanner-level input validation
    if (normalized.isEmpty) {
      _reportError('Scanned input is empty or contains only whitespace.');
      return null;
    }

    if (normalized.length < _configuration.minInputLength) {
      _reportError(
        'Scanned code "$normalized" is too short (min ${_configuration.minInputLength} chars).',
      );
      return null;
    }

    if (normalized.length > _configuration.maxInputLength) {
      _reportError(
        'Scanned code exceeds maximum length (${_configuration.maxInputLength} chars).',
      );
      return null;
    }

    final now = _now();

    // 2. Duplicate suppression check
    if (!_configuration.allowDuplicates) {
      final lastSeen = _recentScanTimestamps[normalized];
      if (lastSeen != null) {
        final elapsed = now.difference(lastSeen);
        if (elapsed < _configuration.duplicateSuppressionDuration) {
          // Suppressed duplicate camera frame or double-read
          return null;
        }
      }
    }

    // 3. Construct valid result
    final result = SmartScanResult.valid(
      rawValue: rawValue,
      format: format,
      source: source,
      timestamp: now,
      sessionId: sessionId ?? _configuration.sessionId,
      deviceId: deviceId ?? _configuration.deviceId,
    );

    // Record timestamp for suppression
    _recentScanTimestamps[normalized] = now;
    _purgeOldSuppressionTimestamps(now);

    // 4. Update in-memory history (newest at index 0)
    _history.insert(0, result);
    _trimHistory();

    // 5. Emit event
    if (!_scansController.isClosed) {
      _scansController.add(result);
    }

    // 6. Handle single-scan mode termination
    if (_configuration.mode == ScannerMode.single || _configuration.stopOnFirstResult) {
      pause();
    }

    return result;
  }

  /// Clears in-memory scan history.
  void clearHistory() {
    _checkDisposed();
    _history.clear();
  }

  /// Disposes controller streams and cleans up memory.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _status = ScannerStatus.stopped;
    _recentScanTimestamps.clear();
    _history.clear();
    _scansController.close();
    _statusController.close();
    _errorController.close();
  }

  void _updateStatus(ScannerStatus next) {
    if (_status == next) return;
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  void _reportError(String message) {
    _lastErrorMessage = message;
    if (!_errorController.isClosed) {
      _errorController.add(message);
    }
  }

  void _trimHistory() {
    while (_history.length > _configuration.maxHistorySize) {
      _history.removeLast();
    }
  }

  void _purgeOldSuppressionTimestamps(DateTime now) {
    final cutoff = _configuration.duplicateSuppressionDuration * 2;
    _recentScanTimestamps.removeWhere((_, time) => now.difference(time) > cutoff);
  }

  void _checkDisposed() {
    if (_isDisposed) {
      throw StateError('Cannot operate on a disposed SmartScannerController.');
    }
  }
}
