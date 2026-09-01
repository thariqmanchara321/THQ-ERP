import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'device_installation_service.dart';

import '../models/sale.dart';
import '../models/sale_detail.dart';

class SalesService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Sale>> getSales({required String tenantId}) async {
    final activation = await _activation(tenantId);
    final result = await _supabase.rpc(
      'pos_sales_today_v473',
      params: {
        'p_tenant_id': tenantId,
        'p_device_id': activation.deviceId,
        'p_day': _dateOnly(DateTime.now()),
      },
    );

    return (result as List<dynamic>)
        .map((row) => Sale.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }


  Future<Map<String, dynamic>> createSale({
    required String tenantId,
    required String customerId,
    required DateTime saleDate,
    required DateTime? dueDate,
    required List<Map<String, dynamic>> items,
    required double additionalCharges,
    double roundOff = 0,
    required double initialPayment,
    required String paymentMethod,
    required String paymentReference,
    required String notes,
    String? requestId,
  }) async {
    final result = await _supabase.rpc(
      'sales_create_v489',
      params: {
        'p_tenant_id': tenantId,
        'p_customer_id': customerId,
        'p_sale_date': _dateOnly(saleDate),
        'p_due_date': dueDate == null ? null : _dateOnly(dueDate),
        'p_items': items,
        'p_additional_charges': additionalCharges,
        'p_round_off': roundOff,
        'p_initial_payment': initialPayment,
        'p_payment_method': paymentMethod,
        'p_payment_reference': paymentReference.trim(),
        'p_notes': notes.trim(),
        'p_request_id': requestId ?? const Uuid().v4(),
        ...await _originParams(tenantId),
      },
    );

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }

    throw Exception('Unexpected response while creating sale.');
  }

  Future<String?> resolveSaleId({
    required String tenantId,
    required String saleNumber,
  }) async {
    final result = await _supabase.rpc(
      'sales_resolve_number_v32',
      params: {'p_tenant_id': tenantId, 'p_sale_number': saleNumber},
    );
    final value = result?.toString() ?? '';
    return value.isEmpty || value == 'null' ? null : value;
  }

  Future<SaleDetail> getSaleDetail({
    required String tenantId,
    required String saleId,
  }) async {
    final result = await _supabase.rpc(
      'sales_get_detail_v495',
      params: {'p_tenant_id': tenantId, 'p_sale_id': saleId},
    );
    if (result is Map) {
      return SaleDetail.fromMap(Map<String, dynamic>.from(result));
    }
    throw Exception('Unexpected sale detail response.');
  }

  Future<Map<String, dynamic>> addPayment({
    required String tenantId,
    required String saleId,
    required double amount,
    required String paymentMethod,
    required String referenceNumber,
    required String notes,
    String? requestId,
  }) async {
    final result = await _supabase.rpc(
      'sales_add_payment_v47',
      params: {
        'p_tenant_id': tenantId,
        'p_sale_id': saleId,
        'p_amount': amount,
        'p_payment_method': paymentMethod,
        'p_reference_number': referenceNumber.trim(),
        'p_notes': notes.trim(),
        'p_request_id': requestId ?? const Uuid().v4(),
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw Exception('Unexpected payment response.');
  }

  Future<void> updateMetadata({
    required String tenantId,
    required String saleId,
    required String customerId,
    required DateTime? dueDate,
    required String notes,
  }) async {
    await _supabase.rpc(
      'sales_update_metadata_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_sale_id': saleId,
        'p_customer_id': customerId,
        'p_due_date': dueDate == null ? null : _dateOnly(dueDate),
        'p_notes': notes.trim(),
      },
    );
  }

  Future<DeviceActivation> _activation(String tenantId) async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null || activation.tenantId != tenantId) {
      throw StateError('This system is not activated for this business.');
    }
    return activation;
  }

  Future<Map<String, dynamic>> getReturnStatus({
    required String tenantId,
    required String saleId,
  }) async {
    final result = await _supabase.rpc(
      'transaction_return_status_v45',
      params: {
        'p_tenant_id': tenantId,
        'p_entity_type': 'sale',
        'p_entity_id': saleId,
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{'status': 'not_returned'};
  }

  Future<Map<String, dynamic>> createReturn({
    required String tenantId,
    required String saleId,
    required List<Map<String, dynamic>> items,
    required String reason,
    String? requestId,
  }) async {
    final origin = await _originParams(tenantId);
    final result = await _supabase.rpc(
      'sales_return_create_v483',
      params: {
        'p_tenant_id': tenantId,
        'p_sale_id': saleId,
        'p_items': items,
        'p_reason': reason.trim(),
        'p_device_id': origin['p_device_id'],
        'p_request_id': requestId ?? const Uuid().v4(),
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw Exception('Unexpected sales return response.');
  }

  Future<void> voidSale({
    required String tenantId,
    required String saleId,
    required String reason,
    String? requestId,
  }) async {
    final origin = await _originParams(tenantId);
    await _supabase.rpc(
      'sales_void_v483',
      params: {
        'p_tenant_id': tenantId,
        'p_sale_id': saleId,
        'p_reason': reason.trim(),
        'p_device_id': origin['p_device_id'],
        'p_request_id': requestId ?? const Uuid().v4(),
      },
    );
  }

  Future<Map<String, dynamic>> _originParams(String tenantId) async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null || activation.tenantId != tenantId) {
      throw StateError('This system is not activated for this business.');
    }
    return {
      'p_location_id': activation.locationId,
      'p_device_id': activation.deviceId,
    };
  }

  String _dateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');

    final month = value.month.toString().padLeft(2, '0');

    final day = value.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}
