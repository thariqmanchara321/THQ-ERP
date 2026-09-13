import 'package:supabase_flutter/supabase_flutter.dart';

import 'gst_v520_route_guard.dart';

class RestaurantService {
  SupabaseClient get _s => Supabase.instance.client;
  final GstV520RouteGuard _guard = GstV520RouteGuard();

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

  Future<List<Map<String, dynamic>>> waiters(
    String tenantId,
    String locationId,
    String deviceId,
  ) async {
    final result = await _s.rpc(
      'restaurant_waiters_list_v610',
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
      'restaurant_orders_list_v610',
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
    int guestCount = 1,
    String? waiterUserId,
    String orderNote = '',
  }) async {
    final result = await _s.rpc(
      'restaurant_order_create_v610',
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
        'p_guest_count': guestCount,
        'p_waiter_user_id': waiterUserId,
        'p_order_note': orderNote.trim(),
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant order response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> updateOrder({
    required String tenantId,
    required String orderId,
    required String deviceId,
    String? tableId,
    String? customerId,
    int? guestCount,
    String? waiterUserId,
    String? orderNote,
    String? chefNote,
    String? deliveryAddress,
  }) async {
    final result = await _s.rpc(
      'restaurant_order_update_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_order_id': orderId,
        'p_device_id': deviceId,
        'p_table_id': tableId,
        'p_customer_id': customerId,
        'p_guest_count': guestCount,
        'p_waiter_user_id': waiterUserId,
        'p_order_note': orderNote,
        'p_chef_note': chefNote,
        'p_delivery_address': deliveryAddress,
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant order update response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> addItems({
    required String tenantId,
    required String orderId,
    required String deviceId,
    required List<Map<String, dynamic>> items,
  }) async {
    final result = await _s.rpc(
      'restaurant_order_add_items_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_order_id': orderId,
        'p_device_id': deviceId,
        'p_items': items,
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant add-items response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> dashboardSummary({
    required String tenantId,
    required String locationId,
    required String deviceId,
  }) async {
    final result = await _s.rpc(
      'restaurant_operations_summary_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_device_id': deviceId,
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant dashboard response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<List<Map<String, dynamic>>> waitlist({
    required String tenantId,
    required String locationId,
    required String deviceId,
    String status = 'live',
    int limit = 200,
  }) async {
    final result = await _s.rpc(
      'restaurant_waitlist_list_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_device_id': deviceId,
        'p_status': status,
        'p_limit': limit,
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant waitlist response.');
    }
    final map = Map<String, dynamic>.from(result);
    return (map['entries'] as List? ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
  }

  Future<Map<String, dynamic>> addWaitlistGuest({
    required String tenantId,
    required String locationId,
    required String deviceId,
    required String guestName,
    required String phone,
    required int guestCount,
    required int estimatedWaitMinutes,
    String preferredArea = '',
    String note = '',
  }) async {
    final result = await _s.rpc(
      'restaurant_waitlist_add_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_device_id': deviceId,
        'p_guest_name': guestName.trim(),
        'p_phone': phone.trim(),
        'p_guest_count': guestCount,
        'p_estimated_wait_minutes': estimatedWaitMinutes,
        'p_preferred_area': preferredArea.trim(),
        'p_note': note.trim(),
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant waitlist-add response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> setWaitlistStatus({
    required String tenantId,
    required String waitlistId,
    required String deviceId,
    required String status,
    String? tableId,
    String note = '',
  }) async {
    final result = await _s.rpc(
      'restaurant_waitlist_status_set_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_waitlist_id': waitlistId,
        'p_device_id': deviceId,
        'p_status': status,
        'p_table_id': tableId,
        'p_note': note.trim(),
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant waitlist-status response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<List<Map<String, dynamic>>> kitchenQueue({
    required String tenantId,
    required String locationId,
    required String deviceId,
    String status = 'live',
    int limit = 100,
  }) async {
    final result = await _s.rpc(
      'restaurant_kitchen_queue_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_device_id': deviceId,
        'p_status': status,
        'p_limit': limit,
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant kitchen queue response.');
    }
    final map = Map<String, dynamic>.from(result);
    return (map['kots'] as List? ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
  }

  Future<Map<String, dynamic>> setKotStatus({
    required String tenantId,
    required String kotId,
    required String deviceId,
    required String status,
  }) async {
    final result = await _s.rpc(
      'restaurant_kot_status_set_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_kot_id': kotId,
        'p_device_id': deviceId,
        'p_status': status,
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant KOT status response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> splitOrder({
    required String tenantId,
    required String sourceOrderId,
    required String deviceId,
    required String toTableId,
    required List<Map<String, dynamic>> items,
    required int guestCount,
    String note = '',
  }) async {
    final result = await _s.rpc(
      'restaurant_order_split_safe_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_source_order_id': sourceOrderId,
        'p_device_id': deviceId,
        'p_to_table_id': toTableId,
        'p_items': items,
        'p_guest_count': guestCount,
        'p_note': note.trim(),
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant split-order response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> mergeOrders({
    required String tenantId,
    required String targetOrderId,
    required String sourceOrderId,
    required String deviceId,
    String note = '',
  }) async {
    final result = await _s.rpc(
      'restaurant_orders_merge_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_target_order_id': targetOrderId,
        'p_source_order_id': sourceOrderId,
        'p_device_id': deviceId,
        'p_note': note.trim(),
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant order merge response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> reserveTable({
    required String tenantId,
    required String tableId,
    required String deviceId,
    required String reservationName,
    required String reservationPhone,
    required DateTime reservationAt,
    String reservationNote = '',
  }) async {
    final result = await _s.rpc(
      'restaurant_table_reservation_set_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_table_id': tableId,
        'p_device_id': deviceId,
        'p_reservation_name': reservationName.trim(),
        'p_reservation_phone': reservationPhone.trim(),
        'p_reservation_at': reservationAt.toIso8601String(),
        'p_reservation_note': reservationNote.trim(),
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant reservation response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> clearTableReservation({
    required String tenantId,
    required String tableId,
    required String deviceId,
    String note = '',
  }) async {
    final result = await _s.rpc(
      'restaurant_table_reservation_clear_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_table_id': tableId,
        'p_device_id': deviceId,
        'p_note': note.trim(),
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected reservation-clear response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> setTableOperationalStatus({
    required String tenantId,
    required String tableId,
    required String deviceId,
    required String status,
    String note = '',
  }) async {
    final result = await _s.rpc(
      'restaurant_table_status_set_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_table_id': tableId,
        'p_device_id': deviceId,
        'p_status': status,
        'p_note': note.trim(),
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant table-status response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> transferTable({
    required String tenantId,
    required String orderId,
    required String deviceId,
    required String toTableId,
    String note = '',
  }) async {
    final result = await _s.rpc(
      'restaurant_order_transfer_table_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_order_id': orderId,
        'p_device_id': deviceId,
        'p_to_table_id': toTableId,
        'p_note': note.trim(),
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant table transfer response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> cancelItem({
    required String tenantId,
    required String orderId,
    required String orderItemId,
    required String deviceId,
    required double cancelQuantity,
    required String reason,
  }) async {
    final result = await _s.rpc(
      'restaurant_order_cancel_item_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_order_id': orderId,
        'p_order_item_id': orderItemId,
        'p_device_id': deviceId,
        'p_cancel_quantity': cancelQuantity,
        'p_reason': reason.trim(),
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected restaurant item cancellation response.');
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
    final rpc = await _guard.route(
      tenantId: tenantId,
      channel: 'pos',
      routeKey: 'restaurant_bill',
      deviceId: deviceId,
    );

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
        'Authoritative POS restaurant GST billing failed. Legacy fallback is '
        'disabled. $error',
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
