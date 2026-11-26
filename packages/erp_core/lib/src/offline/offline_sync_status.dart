/// Canonical synchronization status and conflict codes for offline transactions.
library;

/// Canonical status of an offline sale transaction in the local durability queue.
enum OfflineSyncStatus {
  pending('pending'),
  syncing('syncing'),
  synced('synced'),
  conflict('conflict'),
  error('error'),
  cancelled('cancelled');

  final String value;
  const OfflineSyncStatus(this.value);

  static OfflineSyncStatus fromString(String raw) {
    final lower = raw.trim().toLowerCase();
    for (final status in OfflineSyncStatus.values) {
      if (status.value == lower) return status;
    }
    return OfflineSyncStatus.error;
  }

  bool get isPending => this == OfflineSyncStatus.pending;
  bool get isSyncing => this == OfflineSyncStatus.syncing;
  bool get isSynced => this == OfflineSyncStatus.synced;
  bool get isConflict => this == OfflineSyncStatus.conflict;
  bool get isError => this == OfflineSyncStatus.error;
  bool get isCancelled => this == OfflineSyncStatus.cancelled;
}

/// Standardized offline synchronization conflict and rejection codes.
abstract final class OfflineConflictCodes {
  /// Unit price on server differs from cached price when invoice was created.
  static const String priceChanged = 'PRICE_CHANGED';

  /// Tax rate or GST classification changed between cache and sync.
  static const String taxChanged = 'TAX_CHANGED';

  /// Insufficient inventory available on server for one or more items.
  static const String stockConflict = 'STOCK_CONFLICT';

  /// Serial number already sold, allocated, or no longer available on server.
  static const String serialConflict = 'SERIAL_CONFLICT';

  /// General server-side business validation rejection.
  static const String serverValidation = 'SERVER_VALIDATION';

  /// Authentication token or device session expired during sync.
  static const String authExpired = 'AUTH_EXPIRED';

  /// Unexpected or unhandled server error during sync processing.
  static const String unexpectedError = 'UNEXPECTED_ERROR';

  /// List of all standard recognized conflict codes.
  static const List<String> all = [
    priceChanged,
    taxChanged,
    stockConflict,
    serialConflict,
    serverValidation,
    authExpired,
    unexpectedError,
  ];
}
