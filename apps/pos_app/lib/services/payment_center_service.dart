import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/payment_pending.dart';

class PaymentCenterService {
  SupabaseClient get _s => Supabase.instance.client;
  Future<PendingPaymentsData> load(String tenantId) async {
    final r = await _s.rpc(
      'payments_pending_list',
      params: {'p_tenant_id': tenantId, 'p_limit': 500},
    );
    if (r is! Map) throw Exception('Unexpected payments response.');
    return PendingPaymentsData.fromMap(Map<String, dynamic>.from(r));
  }
}
