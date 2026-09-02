import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class GstV520RequestLease {
  const GstV520RequestLease({
    required this.requestId,
    required this.storagePrefix,
    required this.fingerprint,
    required this.managed,
  });

  final String requestId;
  final String storagePrefix;
  final String fingerprint;
  final bool managed;
}

/// Keeps an idempotency request ID stable across transport failures and app
/// restarts for the same immutable transaction payload.
///
/// A changed payload gets a new request ID. A successful authoritative write
/// clears the stored lease. Caller-supplied request IDs are never overwritten.
class GstV520RequestIdStore {
  GstV520RequestIdStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<GstV520RequestLease> acquire({
    required String tenantId,
    required String operation,
    required Map<String, dynamic> payload,
    String? providedRequestId,
  }) async {
    final supplied = providedRequestId?.trim() ?? '';
    final fingerprint = _fingerprint(jsonEncode(payload));

    if (supplied.isNotEmpty) {
      return GstV520RequestLease(
        requestId: supplied,
        storagePrefix: '',
        fingerprint: fingerprint,
        managed: false,
      );
    }

    final safeOperation = operation.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final prefix = 'thq_v520_req_${tenantId}_$safeOperation';
    final fingerprintKey = '${prefix}_fp';
    final requestKey = '${prefix}_id';

    final existingFingerprint = await _storage.read(key: fingerprintKey);
    final existingRequest = await _storage.read(key: requestKey);

    if (existingFingerprint == fingerprint &&
        existingRequest != null &&
        existingRequest.trim().isNotEmpty) {
      return GstV520RequestLease(
        requestId: existingRequest.trim(),
        storagePrefix: prefix,
        fingerprint: fingerprint,
        managed: true,
      );
    }

    final requestId = const Uuid().v4();
    await _storage.write(key: fingerprintKey, value: fingerprint);
    await _storage.write(key: requestKey, value: requestId);

    return GstV520RequestLease(
      requestId: requestId,
      storagePrefix: prefix,
      fingerprint: fingerprint,
      managed: true,
    );
  }

  Future<void> complete(GstV520RequestLease lease) async {
    if (!lease.managed || lease.storagePrefix.isEmpty) return;

    final fingerprintKey = '${lease.storagePrefix}_fp';
    final requestKey = '${lease.storagePrefix}_id';
    final currentFingerprint = await _storage.read(key: fingerprintKey);
    final currentRequest = await _storage.read(key: requestKey);

    // Do not clear a newer lease if another transaction has already replaced it.
    if (currentFingerprint == lease.fingerprint &&
        currentRequest == lease.requestId) {
      await _storage.delete(key: fingerprintKey);
      await _storage.delete(key: requestKey);
    }
  }

  String _fingerprint(String value) {
    // Deterministic FNV-1a 32-bit hash. Unlike String.hashCode, this is stable
    // across app restarts and is only used to identify the local retry payload.
    var hash = 0x811C9DC5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
