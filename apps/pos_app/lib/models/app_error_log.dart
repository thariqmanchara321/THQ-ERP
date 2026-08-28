class AppErrorLog {
  final String id;
  final String appKey;
  final String severity;
  final String message;
  final String? stackTrace;
  final DateTime? createdAt;
  final String? userId;
  const AppErrorLog({
    required this.id,
    required this.appKey,
    required this.severity,
    required this.message,
    required this.stackTrace,
    required this.createdAt,
    required this.userId,
  });
  factory AppErrorLog.fromMap(Map<String, dynamic> m) => AppErrorLog(
    id: m['id']?.toString() ?? '',
    appKey: m['app_key']?.toString() ?? '',
    severity: m['severity']?.toString() ?? 'error',
    message: m['message']?.toString() ?? '',
    stackTrace: m['stack_trace']?.toString(),
    createdAt: DateTime.tryParse(m['created_at']?.toString() ?? ''),
    userId: m['user_id']?.toString(),
  );
}
