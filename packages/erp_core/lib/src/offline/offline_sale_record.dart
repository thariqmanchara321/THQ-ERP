import 'offline_sync_status.dart';

/// Canonical record representing an offline sale transaction in durable storage.
class OfflineSaleRecord {
  final String requestId;
  final String localInvoiceNumber;
  final String status;
  final Map<String, dynamic> payload;
  final int attempts;
  final String? conflictCode;
  final String? conflictMessage;
  final Map<String, dynamic>? serverResponse;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool printRequested;

  const OfflineSaleRecord({
    required this.requestId,
    required this.localInvoiceNumber,
    required this.status,
    required this.payload,
    required this.attempts,
    this.conflictCode,
    this.conflictMessage,
    this.serverResponse,
    required this.createdAt,
    required this.updatedAt,
    this.printRequested = false,
  });

  /// Mobile POS compatibility alias: `localNumber` maps to `localInvoiceNumber`.
  String get localNumber => localInvoiceNumber;

  /// Convenience status inspection getters.
  bool get isPending => status == OfflineSyncStatus.pending.value;
  bool get isSyncing => status == OfflineSyncStatus.syncing.value;
  bool get isSynced => status == OfflineSyncStatus.synced.value;
  bool get isConflict => status == OfflineSyncStatus.conflict.value;
  bool get isError => status == OfflineSyncStatus.error.value;
  bool get isCancelled => status == OfflineSyncStatus.cancelled.value;

  OfflineSyncStatus get syncStatus => OfflineSyncStatus.fromString(status);

  OfflineSaleRecord copyWith({
    String? requestId,
    String? localInvoiceNumber,
    String? status,
    Map<String, dynamic>? payload,
    int? attempts,
    String? conflictCode,
    String? conflictMessage,
    Map<String, dynamic>? serverResponse,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? printRequested,
  }) {
    return OfflineSaleRecord(
      requestId: requestId ?? this.requestId,
      localInvoiceNumber: localInvoiceNumber ?? this.localInvoiceNumber,
      status: status ?? this.status,
      payload: payload ?? this.payload,
      attempts: attempts ?? this.attempts,
      conflictCode: conflictCode ?? this.conflictCode,
      conflictMessage: conflictMessage ?? this.conflictMessage,
      serverResponse: serverResponse ?? this.serverResponse,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      printRequested: printRequested ?? this.printRequested,
    );
  }

  Map<String, dynamic> toMap() => {
        'request_id': requestId,
        'local_invoice_number': localInvoiceNumber,
        'status': status,
        'payload': payload,
        'attempts': attempts,
        if (conflictCode != null) 'conflict_code': conflictCode,
        if (conflictMessage != null) 'conflict_message': conflictMessage,
        if (serverResponse != null) 'server_response': serverResponse,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'print_requested': printRequested,
      };

  factory OfflineSaleRecord.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic raw) {
      if (raw is DateTime) return raw;
      if (raw == null) return DateTime.now();
      return DateTime.tryParse(raw.toString()) ?? DateTime.now();
    }

    final serverRaw = map['server_response'] ?? map['server_response_json'];
    Map<String, dynamic>? server;
    if (serverRaw is Map) {
      server = Map<String, dynamic>.from(serverRaw);
    }

    return OfflineSaleRecord(
      requestId: map['request_id']?.toString() ?? '',
      localInvoiceNumber:
          (map['local_invoice_number'] ?? map['local_number'])?.toString() ?? '',
      status: map['status']?.toString() ?? 'pending',
      payload: map['payload'] is Map
          ? Map<String, dynamic>.from(map['payload'] as Map)
          : const <String, dynamic>{},
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      conflictCode: map['conflict_code']?.toString(),
      conflictMessage: map['conflict_message']?.toString(),
      serverResponse: server,
      createdAt: parseDate(map['created_at']),
      updatedAt: parseDate(map['updated_at'] ?? map['created_at']),
      printRequested: map['print_requested'] == true || map['print_requested'] == 1,
    );
  }
}
