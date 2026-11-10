import 'dart:async';

/// Manages and checks operational readiness for software updates across
/// THQ Business and THQ POS to prevent interrupting in-flight sales,
/// accounting postings, receipt printing, and offline transactions.
class ErpUpdateReadinessService {
  static final ErpUpdateReadinessService _instance =
      ErpUpdateReadinessService._internal();
  factory ErpUpdateReadinessService() => _instance;
  ErpUpdateReadinessService._internal();

  final Map<String, String> _activeOperations = <String, String>{};
  int _unsyncedQueueCount = 0;
  bool _installOnCloseScheduled = false;

  final StreamController<bool> _readinessStreamController =
      StreamController<bool>.broadcast();

  Stream<bool> get onReadinessChanged => _readinessStreamController.stream;

  /// True if all financial, sync, and print operations are idle.
  bool get isSafeToUpdate =>
      _activeOperations.isEmpty && _unsyncedQueueCount == 0;

  /// Indicates if the user chose to defer install until the app closes.
  bool get isInstallOnCloseScheduled => _installOnCloseScheduled;

  /// Number of in-flight critical operations.
  int get activeOperationCount => _activeOperations.length;

  /// Number of offline records waiting to be synced.
  int get unsyncedQueueCount => _unsyncedQueueCount;

  /// Returns user-friendly descriptions of all blockers.
  List<String> get activeOperationReasons {
    final reasons = <String>[];
    if (_unsyncedQueueCount > 0) {
      reasons.add(
        '$_unsyncedQueueCount unsynced offline transactions in queue',
      );
    }
    reasons.addAll(_activeOperations.values);
    return reasons;
  }

  /// Summary message suitable for display in update dialogs or banners.
  String get summaryBlockReason {
    if (isSafeToUpdate) return '';
    return activeOperationReasons.join('; ');
  }

  /// Updates count of unsynced offline invoices/transactions.
  void setUnsyncedQueueCount(int count) {
    _unsyncedQueueCount = count < 0 ? 0 : count;
    _notifyReadiness();
  }

  /// Begins tracking a critical business operation.
  /// Returns a token that MUST be passed to [endOperation] when done.
  String beginOperation(String key, String description) {
    final token = '${key}_${DateTime.now().microsecondsSinceEpoch}';
    _activeOperations[token] = description;
    _notifyReadiness();
    return token;
  }

  /// Wraps an async business operation with automatic lifecycle management.
  Future<T> runWithProtection<T>({
    required String key,
    required String description,
    required Future<T> Function() operation,
  }) async {
    final token = beginOperation(key, description);
    try {
      return await operation();
    } finally {
      endOperation(token);
    }
  }

  /// Ends a previously registered critical operation.
  void endOperation(String token) {
    if (_activeOperations.remove(token) != null) {
      _notifyReadiness();
    }
  }

  /// Schedules installation on next clean application exit.
  void scheduleInstallOnClose(bool schedule) {
    _installOnCloseScheduled = schedule;
    _notifyReadiness();
  }

  void _notifyReadiness() {
    _readinessStreamController.add(isSafeToUpdate);
  }

  void reset() {
    _activeOperations.clear();
    _unsyncedQueueCount = 0;
    _installOnCloseScheduled = false;
    _notifyReadiness();
  }
}
