/// Result of an offline synchronization batch operation.
class OfflineSyncResult {
  final int attempted;
  final int synced;
  final int conflicts;
  final int pending;

  const OfflineSyncResult({
    required this.attempted,
    required this.synced,
    required this.conflicts,
    required this.pending,
  });

  /// Positional constructor for compatibility with MobileSyncResult(attempted, synced, conflicts, pending)
  const OfflineSyncResult.positional(
    this.attempted,
    this.synced,
    this.conflicts,
    this.pending,
  );

  bool get isFullySynced => attempted > 0 && synced == attempted;
  bool get hasConflicts => conflicts > 0;
  bool get hasFailures => conflicts > 0 || pending > 0;

  Map<String, dynamic> toMap() => {
        'attempted': attempted,
        'synced': synced,
        'conflicts': conflicts,
        'pending': pending,
      };
}
