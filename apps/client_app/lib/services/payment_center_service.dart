import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import '../models/payment_pending.dart';
import 'location_scope_service.dart';

class PaymentCenterService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<PendingPaymentsData> load(ClientSession session) async {
    final result = await _supabase.rpc(
      'payments_pending_list_v4',
      params: {
        'p_tenant_id': session.business.id,
        'p_location_id': LocationScopeService.currentForRead(session),
        'p_limit': 500,
      },
    );
    if (result is! Map) throw Exception('Unexpected payments response.');
    return PendingPaymentsData.fromMap(Map<String, dynamic>.from(result));
  }
}
