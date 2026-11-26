import 'offline_sync_status.dart';

/// Structured verification result of a backend synchronization RPC response.
class OfflineSyncVerification {
  final bool isSuccess;
  final bool isConflict;
  final bool isAuthoritativeGst;
  final String? gstSnapshotId;
  final String? gstJournalId;
  final String? conflictCode;
  final String? conflictMessage;
  final Map<String, dynamic> rawResponse;

  const OfflineSyncVerification({
    required this.isSuccess,
    required this.isConflict,
    required this.isAuthoritativeGst,
    this.gstSnapshotId,
    this.gstJournalId,
    this.conflictCode,
    this.conflictMessage,
    required this.rawResponse,
  });
}

/// Verifies server synchronization responses against GST compliance and conflict rules.
abstract final class OfflineSyncVerifier {
  /// Evaluates an RPC response returned by the backend sync endpoint.
  ///
  /// Checks for conflict indicators (`ok == false` or `status == 'conflict'`),
  /// extracts conflict codes and messages, and verifies authoritative GST recovery evidence.
  static OfflineSyncVerification verify(dynamic rawResponse) {
    final map = rawResponse is Map
        ? Map<String, dynamic>.from(rawResponse)
        : const <String, dynamic>{};

    final isExplicitConflict = map['status']?.toString() == OfflineSyncStatus.conflict.value ||
        map['ok'] == false;

    if (isExplicitConflict) {
      final code = map['code']?.toString() ??
          map['conflict_code']?.toString() ??
          OfflineConflictCodes.serverValidation;
      final message = map['message']?.toString() ??
          map['conflict_message']?.toString() ??
          'Server rejected offline transaction.';
      return OfflineSyncVerification(
        isSuccess: false,
        isConflict: true,
        isAuthoritativeGst: false,
        conflictCode: code,
        conflictMessage: message,
        rawResponse: map,
      );
    }

    final isAuthGst = map['authoritative_gst'] == true;
    final snapshotId = map['gst_snapshot_id']?.toString();
    final journalId = map['gst_journal_id']?.toString();

    // A synchronized sale is valid only if the server returns authoritative GST evidence.
    final hasValidGstEvidence = isAuthGst && snapshotId != null && journalId != null;

    if (!hasValidGstEvidence) {
      return OfflineSyncVerification(
        isSuccess: false,
        isConflict: false,
        isAuthoritativeGst: false,
        gstSnapshotId: snapshotId,
        gstJournalId: journalId,
        conflictCode: OfflineConflictCodes.unexpectedError,
        conflictMessage: 'Sync response is missing authoritative GST snapshot or journal ID.',
        rawResponse: map,
      );
    }

    return OfflineSyncVerification(
      isSuccess: true,
      isConflict: false,
      isAuthoritativeGst: true,
      gstSnapshotId: snapshotId,
      gstJournalId: journalId,
      rawResponse: map,
    );
  }
}
