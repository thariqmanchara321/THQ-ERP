import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'device_installation_service.dart';
import 'location_scope_service.dart';

import '../models/purchase.dart';
import '../models/purchase_detail.dart';

class PurchaseService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Purchase>> getPurchases({required String tenantId}) async {
    final result = await _supabase.rpc(
      'purchases_list_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': LocationScopeService.selectedLocationId.value,
      },
    );

    final rows = result as List<dynamic>;

    return rows
        .map((row) => Purchase.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> createPurchase({
    required String tenantId,
    required String supplierId,
    required String supplierInvoiceNumber,
    required DateTime purchaseDate,
    required DateTime? dueDate,
    required List<Map<String, dynamic>> items,
    required double additionalCharges,
    double roundOff = 0,
    required double initialPayment,
    required String paymentMethod,
    required String notes,
    String? locationId,
    String? requestId,
  }) async {
    final result = await _supabase.rpc(
      'purchases_create_v489',
      params: {
        'p_tenant_id': tenantId,
        'p_supplier_id': supplierId,
        'p_supplier_invoice_number': supplierInvoiceNumber.trim(),
        'p_purchase_date': _dateOnly(purchaseDate),
        'p_due_date': dueDate == null ? null : _dateOnly(dueDate),
        'p_items': items,
        'p_additional_charges': additionalCharges,
        'p_round_off': roundOff,
        'p_initial_payment': initialPayment,
        'p_payment_method': paymentMethod,
        'p_notes': notes.trim(),
        'p_request_id': requestId ?? const Uuid().v4(),
        ...await _originParams(tenantId, locationId: locationId),
      },
    );

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }

    throw Exception('Unexpected response while creating purchase.');
  }

  Future<PurchaseDetail> getPurchaseDetail({
    required String tenantId,
    required String purchaseId,
  }) async {
    final result = await _supabase.rpc(
      'purchases_get_detail_v32',
      params: {'p_tenant_id': tenantId, 'p_purchase_id': purchaseId},
    );

    if (result is Map) {
      return PurchaseDetail.fromMap(Map<String, dynamic>.from(result));
    }

    throw Exception('Unexpected purchase detail response.');
  }

  Future<Map<String, dynamic>> addPayment({
    required String tenantId,
    required String purchaseId,
    required double amount,
    required String paymentMethod,
    required String referenceNumber,
    required String notes,
    String? requestId,
  }) async {
    final result = await _supabase.rpc(
      'purchases_add_payment_v47',
      params: {
        'p_tenant_id': tenantId,
        'p_purchase_id': purchaseId,
        'p_amount': amount,
        'p_payment_method': paymentMethod,
        'p_reference_number': referenceNumber.trim(),
        'p_notes': notes.trim(),
        'p_request_id': requestId ?? const Uuid().v4(),
      },
    );

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }

    throw Exception('Unexpected payment response.');
  }

  Future<Map<String, dynamic>> getReturnStatus({
    required String tenantId,
    required String purchaseId,
  }) async {
    final result = await _supabase.rpc(
      'transaction_return_status_v45',
      params: {
        'p_tenant_id': tenantId,
        'p_entity_type': 'purchase',
        'p_entity_id': purchaseId,
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{'status': 'not_returned'};
  }

  Future<Map<String, dynamic>> createReturn({
    required String tenantId,
    required String purchaseId,
    required List<Map<String, dynamic>> items,
    required String reason,
  }) async {
    final origin = await _originParams(tenantId);
    final result = await _supabase.rpc(
      'purchase_return_create_v483',
      params: {
        'p_tenant_id': tenantId,
        'p_purchase_id': purchaseId,
        'p_items': items,
        'p_reason': reason.trim(),
        'p_device_id': origin['p_device_id'],
        'p_request_id': const Uuid().v4(),
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw Exception('Unexpected purchase return response.');
  }

  Future<void> voidPurchase({
    required String tenantId,
    required String purchaseId,
    required String reason,
  }) async {
    final origin = await _originParams(tenantId);
    await _supabase.rpc(
      'purchase_void_v483',
      params: {
        'p_tenant_id': tenantId,
        'p_purchase_id': purchaseId,
        'p_reason': reason.trim(),
        'p_device_id': origin['p_device_id'],
        'p_request_id': const Uuid().v4(),
      },
    );
  }

  Future<Map<String, dynamic>> _originParams(
    String tenantId, {
    String? locationId,
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null || activation.tenantId != tenantId) {
      throw StateError('This system is not activated for this business.');
    }
    return {
      'p_location_id':
          locationId ??
          LocationScopeService.selectedLocationId.value ??
          activation.locationId,
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
