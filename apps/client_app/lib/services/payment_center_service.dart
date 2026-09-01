import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import '../models/payment_pending.dart';
import 'location_scope_service.dart';

class PaymentCenterService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<PendingPaymentsData> load(
    ClientSession session, {
    String query = '',
  }) async {
    final result = await _supabase.rpc(
      'payments_party_summary_v491',
      params: {
        'p_tenant_id': session.business.id,
        'p_location_id': LocationScopeService.currentForRead(session),
        'p_query': query,
        'p_limit': 1000,
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected pending-payments response.');
    }
    return PendingPaymentsData.fromMap(Map<String, dynamic>.from(result));
  }

  Future<PartyPaymentDetail> detail(
    ClientSession session, {
    required String partyType,
    required String partyId,
  }) async {
    final result = await _supabase.rpc(
      'payments_party_detail_v491',
      params: {
        'p_tenant_id': session.business.id,
        'p_party_type': partyType,
        'p_party_id': partyId,
        'p_location_id': LocationScopeService.currentForRead(session),
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected party payment detail response.');
    }
    return PartyPaymentDetail.fromMap(Map<String, dynamic>.from(result));
  }
}
