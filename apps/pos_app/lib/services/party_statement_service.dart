import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/party_statement.dart';

class PartyStatementService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<PartyStatement> customerStatement({
    required String tenantId,
    required String customerId,
    DateTime? from,
    DateTime? to,
    String? locationId,
  }) async {
    dynamic result;
    try {
      result = await _supabase.rpc(
        'customers_get_statement_v715',
        params: {
          'p_tenant_id': tenantId,
          'p_customer_id': customerId,
          'p_from': from?.toIso8601String().split('T').first,
          'p_to': to?.toIso8601String().split('T').first,
          'p_location_id': locationId,
        },
      );
    } catch (_) {
      result = await _supabase.rpc(
        'customers_get_statement',
        params: {'p_tenant_id': tenantId, 'p_customer_id': customerId},
      );
    }
    if (result is! Map) {
      throw Exception('Unexpected customer statement response.');
    }
    return PartyStatement.fromMap(Map<String, dynamic>.from(result));
  }

  Future<PartyStatement> supplierStatement({
    required String tenantId,
    required String supplierId,
    DateTime? from,
    DateTime? to,
    String? locationId,
  }) async {
    final result = await _supabase.rpc(
      'suppliers_get_statement_v484',
      params: {
        'p_tenant_id': tenantId,
        'p_supplier_id': supplierId,
        'p_from': from?.toIso8601String().split('T').first,
        'p_to': to?.toIso8601String().split('T').first,
        'p_location_id': locationId,
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected supplier statement response.');
    }
    return PartyStatement.fromMap(Map<String, dynamic>.from(result));
  }
}
