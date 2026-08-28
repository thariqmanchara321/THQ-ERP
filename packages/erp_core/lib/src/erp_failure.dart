/// Standard error shape for operations that need a support reference.
class ErpFailure implements Exception {
  final String code;
  final String message;
  final String? referenceId;
  final bool retryable;

  const ErpFailure({
    required this.code,
    required this.message,
    this.referenceId,
    this.retryable = false,
  });

  @override
  String toString() => referenceId == null
      ? '$code: $message'
      : '$code: $message (Reference: $referenceId)';
}
