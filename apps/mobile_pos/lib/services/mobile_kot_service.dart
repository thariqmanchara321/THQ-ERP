import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pos_session.dart';
import 'gst_v520_route_guard.dart';

class MobileKotService {
  final GstV520RouteGuard _guard = GstV520RouteGuard();
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> create({
    required PosSession session,
    required String requestId,
    required String orderType,
    String? tableId,
    String? customerId,
    required List<Map<String, dynamic>> items,
    String note = '',
  }) async {
    // Validate the Mobile POS v5.2 contract first. KOT itself is not a GST
    // document; authoritative GST is calculated only when the order is billed.
    await _guard.route(
      tenantId: session.tenantId,
      channel: 'mobile_pos',
      routeKey: 'api_contract',
      deviceId: session.deviceId,
    );

    final raw = await _supabase.rpc(
      'mobile_pos_kot_create_v520',
      params: {
        'p_tenant_id': session.tenantId,
        'p_device_id': session.deviceId,
        'p_request_id': requestId,
        'p_order_type': orderType,
        'p_table_id': tableId,
        'p_customer_id': customerId,
        'p_items': items,
        'p_note': note,
        'p_send_now': true,
      },
    );
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
  }
}
