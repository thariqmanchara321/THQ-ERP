import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerAccountService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> account({
    required String tenantId,
    required String customerId,
  }) async {
    final result = await _supabase.rpc(
      'customer_account_v471',
      params: {'p_tenant_id': tenantId, 'p_customer_id': customerId},
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> accounts({
    required String tenantId,
    String query = '',
    int limit = 500,
  }) async {
    final result = await _supabase.rpc(
      'customer_accounts_list_v471',
      params: {
        'p_tenant_id': tenantId,
        'p_query': query.trim().isEmpty ? null : query.trim(),
        'p_limit': limit,
      },
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, dynamic>> receivePayment({
    required String tenantId,
    required String customerId,
    required double amount,
    required String paymentMethod,
    required String requestId,
    String referenceNumber = '',
    String notes = '',
    String? saleId,
    String? locationId,
    String? deviceId,
  }) async {
    final result = await _supabase.rpc(
      'customer_receive_payment_v471',
      params: {
        'p_tenant_id': tenantId,
        'p_customer_id': customerId,
        'p_amount': amount,
        'p_payment_method': paymentMethod,
        'p_reference_number': referenceNumber.trim(),
        'p_notes': notes.trim(),
        'p_sale_id': saleId,
        'p_location_id': locationId,
        'p_device_id': deviceId,
        'p_request_id': requestId,
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }
}
