import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransactionControlService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> list({
    required String tenantId,
    DateTime? from,
    DateTime? to,
    String query = '',
    int limit = 500,
  }) async {
    final result = await _supabase.rpc(
      'platform_transactions_list_v45',
      params: {
        'p_tenant_id': tenantId,
        'p_from': from == null ? null : DateFormat('yyyy-MM-dd').format(from),
        'p_to': to == null ? null : DateFormat('yyyy-MM-dd').format(to),
        'p_query': query.trim().isEmpty ? null : query.trim(),
        'p_limit': limit,
      },
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> safeVoid({
    required String tenantId,
    required String entityType,
    required String entityId,
    required String reason,
  }) async {
    await _supabase.rpc(
      'platform_transaction_void_v44',
      params: {
        'p_tenant_id': tenantId,
        'p_entity_type': entityType,
        'p_entity_id': entityId,
        'p_reason': reason.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> detail({
    required String tenantId,
    required String entityType,
    required String entityId,
  }) async {
    final result = await _supabase.rpc(
      'platform_transaction_detail_v45',
      params: {
        'p_tenant_id': tenantId,
        'p_entity_type': entityType,
        'p_entity_id': entityId,
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> parties({
    required String tenantId,
    required String partyType,
    String query = '',
  }) async {
    final result = await _supabase.rpc(
      'platform_parties_list_v45',
      params: {
        'p_tenant_id': tenantId,
        'p_party_type': partyType,
        'p_query': query.trim().isEmpty ? null : query.trim(),
      },
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> correct({
    required String tenantId,
    required String entityType,
    required String entityId,
    required Map<String, dynamic> patch,
    required String reason,
  }) async {
    final result = await _supabase.rpc(
      'platform_transaction_correct_v45',
      params: {
        'p_tenant_id': tenantId,
        'p_entity_type': entityType,
        'p_entity_id': entityId,
        'p_patch': patch,
        'p_reason': reason.trim(),
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> correctReturn({
    required String tenantId,
    required String entityType,
    required String entityId,
    required Map<String, dynamic> patch,
    required String reason,
  }) async {
    final result = await _supabase.rpc(
      'platform_return_correct_v45',
      params: {
        'p_tenant_id': tenantId,
        'p_entity_type': entityType,
        'p_entity_id': entityId,
        'p_patch': patch,
        'p_reason': reason.trim(),
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<void> correctPayment({
    required String tenantId,
    required String entityType,
    required String paymentId,
    required String paymentMethod,
    required String referenceNumber,
    required String reason,
  }) async {
    await _supabase.rpc(
      'platform_payment_correct_v45',
      params: {
        'p_tenant_id': tenantId,
        'p_entity_type': entityType,
        'p_payment_id': paymentId,
        'p_payment_method': paymentMethod,
        'p_reference_number': referenceNumber.trim(),
        'p_reason': reason.trim(),
      },
    );
  }
}
