import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pos_session.dart';

class MobilePricingService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<Map<String, dynamic>> resolve({
    required PosSession session,
    required String variantId,
    required String? customerId,
    required String? unitId,
    required double quantity,
  }) async {
    final result = await _client.rpc(
      'pricing_resolve_v482',
      params: {
        'p_tenant_id': session.tenantId,
        'p_variant_id': variantId,
        'p_customer_id': customerId,
        'p_unit_id': (unitId == null || unitId.isEmpty) ? null : unitId,
        'p_quantity': quantity,
        'p_location_id': session.locationId,
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected pricing response.');
    }
    return Map<String, dynamic>.from(result);
  }
}
