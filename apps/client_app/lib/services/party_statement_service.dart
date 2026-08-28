import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/party_statement.dart';

class PartyStatementService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<PartyStatement> customerStatement({
    required String tenantId,
    required String customerId,
  }) async {
    final result = await _supabase.rpc(
      'customers_get_statement',
      params: {'p_tenant_id': tenantId, 'p_customer_id': customerId},
    );
    if (result is! Map) {
      throw Exception('Unexpected customer statement response.');
    }
    return PartyStatement.fromMap(Map<String, dynamic>.from(result));
  }

  Future<PartyStatement> supplierStatement({
    required String tenantId,
    required String supplierId,
  }) async {
    final result = await _supabase.rpc(
      'suppliers_get_statement',
      params: {'p_tenant_id': tenantId, 'p_supplier_id': supplierId},
    );
    if (result is! Map) {
      throw Exception('Unexpected supplier statement response.');
    }
    return PartyStatement.fromMap(Map<String, dynamic>.from(result));
  }
}
