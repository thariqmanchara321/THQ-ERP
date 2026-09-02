import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/gst/gst_v520_gateway.dart';

class RestaurantService {
  SupabaseClient get _s => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> tables(
    String tenantId,
    String? locationId,
    String deviceId,
  ) async {
    final result = await _s.rpc(
      'restaurant_tables_list_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_device_id': deviceId,
      },
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> saveTable({
    required String tenantId,
    String? tableId,
    required String locationId,
    required String deviceId,
    required String code,
    required String name,
    required int capacity,
    required String area,
  }) async {
    await _s.rpc(
      'restaurant_table_save_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_table_id': tableId,
        'p_location_id': locationId,
        'p_device_id': deviceId,
        'p_table_code': code.trim(),
        'p_name': name.trim(),
        'p_capacity': capacity,
        'p_area': area.trim(),
        'p_active': true,
      },
    );
  }

  Future<List<Map<String, dynamic>>> orders(
    String tenantId,
    String? locationId,
    String deviceId, {
    bool liveOnly = true,
  }) async {
    final result = await _s.rpc(
      'restaurant_orders_list_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_device_id': deviceId,
        'p_live_only': liveOnly,
        'p_limit': 300,
      },
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createOrder({
    required String tenantId,
    required String locationId,
    required String deviceId,
    required String orderType,
    String? tableId,
    String? customerId,
    required int preparationMinutes,
    required String chefNote,
    required String deliveryAddress,
    required List<Map<String, dynamic>> items,
  }) async {
    // Restaurant order/KOT values are operational previews only. Final GST is
    // authoritative at billOrder().
    final result = await _s.rpc(
      'restaurant_order_create_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_device_id': deviceId,
        'p_order_type': orderType,
        'p_table_id': tableId,
        'p_customer_id': customerId,
        'p_preparation_minutes': preparationMinutes,
        'p_chef_note': chefNote.trim(),
        'p_delivery_address': deliveryAddress.trim(),
        'p_items': items,
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant order response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> detail(
    String tenantId,
    String orderId,
    String deviceId,
  ) async {
    final result = await _s.rpc(
      'restaurant_order_detail_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_order_id': orderId,
        'p_device_id': deviceId,
      },
    );
    if (result is! Map) throw Exception('Unexpected order detail response.');
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> sendKot(
    String tenantId,
    String orderId,
    String deviceId,
    String note,
  ) async {
    final result = await _s.rpc(
      'restaurant_kot_send_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_order_id': orderId,
        'p_device_id': deviceId,
        'p_note': note.trim(),
      },
    );
    if (result is! Map) throw Exception('Unexpected KOT response.');
    return Map<String, dynamic>.from(result);
  }

  Future<void> setStatus(
    String tenantId,
    String orderId,
    String deviceId,
    String status,
  ) => _s.rpc(
    'restaurant_order_set_status_v32',
    params: {
      'p_tenant_id': tenantId,
      'p_order_id': orderId,
      'p_device_id': deviceId,
      'p_status': status,
    },
  );

  Future<Map<String, dynamic>> billOrder({
    required String tenantId,
    required String orderId,
    required String deviceId,
    required String customerId,
    DateTime? dueDate,
    required double initialPayment,
    required String paymentMethod,
    required String paymentReference,
    required double roundOff,
  }) async {
    final gateway = GstV520Gateway(
      client: _s,
      tenantId: tenantId,
      channel: GstV520Channel.client,
      deviceId: deviceId,
    );
    await gateway.initialize();
    final rpc = gateway.routeFor('restaurant_bill');

    try {
      final result = await _s.rpc(
        rpc,
        params: {
          'p_tenant_id': tenantId,
          'p_order_id': orderId,
          'p_device_id': deviceId,
          'p_customer_id': customerId,
          'p_due_date': dueDate == null ? null : _date(dueDate),
          'p_initial_payment': initialPayment,
          'p_payment_method': paymentMethod,
          'p_payment_reference': paymentReference.trim(),
          'p_round_off': roundOff,
        },
      );
      if (result is! Map) throw StateError('Unexpected response from $rpc.');
      return Map<String, dynamic>.from(result);
    } catch (error) {
      throw StateError(
        'Authoritative GST v5.2 restaurant billing failed. Legacy restaurant '
        'billing fallback is disabled. $error',
      );
    }
  }

  Future<void> markBilledByReference(
    String tenantId,
    String orderId,
    String deviceId,
    String saleNumber,
  ) => _s.rpc(
    'restaurant_order_mark_billed_by_reference_v32',
    params: {
      'p_tenant_id': tenantId,
      'p_order_id': orderId,
      'p_device_id': deviceId,
      'p_sale_number': saleNumber,
    },
  );

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
