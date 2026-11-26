/// Summary statistics of offline queue entries by status.
class OfflineQueueSummary {
  final int pending;
  final int conflict;
  final int error;
  final int synced;

  const OfflineQueueSummary({
    required this.pending,
    required this.conflict,
    required this.error,
    required this.synced,
  });

  /// Invoices that require sync, resolution, or attention.
  int get needsAttention => pending + conflict + error;

  /// Total count across all recorded statuses.
  int get total => pending + conflict + error + synced;

  /// Supports dictionary subscript lookup for backward compatibility with `Map<String, int>`
  int operator [](String key) {
    switch (key.trim().toLowerCase()) {
      case 'pending':
        return pending;
      case 'conflict':
        return conflict;
      case 'error':
        return error;
      case 'synced':
        return synced;
      default:
        return 0;
    }
  }

  Map<String, int> toMap() => {
        'pending': pending,
        'conflict': conflict,
        'error': error,
        'synced': synced,
      };

  factory OfflineQueueSummary.fromCounts(Map<String, int> counts) {
    return OfflineQueueSummary(
      pending: counts['pending'] ?? 0,
      conflict: counts['conflict'] ?? 0,
      error: counts['error'] ?? 0,
      synced: counts['synced'] ?? 0,
    );
  }
}
