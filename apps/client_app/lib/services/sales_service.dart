import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../features/gst/gst_v520_gateway.dart';
import '../models/sale.dart';
import '../models/sale_detail.dart';
import 'device_installation_service.dart';
import 'gst_v520_request_id_store.dart';
import 'location_scope_service.dart';

class SalesService {
  SupabaseClient get _supabase => Supabase.instance.client;
  final GstV520RequestIdStore _requestIds = GstV520RequestIdStore();

  Future<List<Sale>> getSales({required String tenantId}) async {
    final result = await _supabase.rpc(
      'sales_list_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': LocationScopeService.selectedLocationId.value,
      },
    );

    final rows = result as List<dynamic>;
    return rows
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
    String? locationId,
    String? requestId,
  }) async {
    final origin = await _originParams(tenantId, locationId: locationId);
    final payload = <String, dynamic>{
      'customer_id': customerId,
      'sale_date': _dateOnly(saleDate),
      'due_date': dueDate == null ? null : _dateOnly(dueDate),
      'items': items,
      'additional_charges': additionalCharges,
      'round_off': roundOff,
      'initial_payment': initialPayment,
      'payment_method': paymentMethod,
      'payment_reference': paymentReference.trim(),
      'notes': notes.trim(),
      'location_id': origin['p_location_id'],
      'device_id': origin['p_device_id'],
    };

    final lease = await _requestIds.acquire(
      tenantId: tenantId,
      operation: 'sale',
      payload: payload,
      providedRequestId: requestId,
    );

    final gateway = GstV520Gateway(
      client: _supabase,
      tenantId: tenantId,
      channel: GstV520Channel.client,
      deviceId: origin['p_device_id']?.toString(),
    );
    await gateway.initialize();
    final rpc = gateway.routeFor('sale');

    try {
      final result = await _supabase.rpc(
        rpc,
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
          'p_location_id': origin['p_location_id'],
          'p_device_id': origin['p_device_id'],
          'p_request_id': lease.requestId,
        },
      );

      if (result is! Map) {
        throw StateError('Unexpected response from $rpc.');
      }

      await _requestIds.complete(lease);
      return Map<String, dynamic>.from(result);
    } catch (error) {
      throw StateError(
        'Authoritative GST v5.2 sale failed. Legacy sale fallback is disabled. '
        'Retry the unchanged invoice to reuse the same request ID. $error',
      );
    }
  }

  Future<SaleDetail> getSaleDetail({
    required String tenantId,
    required String saleId,
  }) async {
    final result = await _supabase.rpc(
      'sales_get_detail_v520',
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
    // Backend migration v5.2 immutability guards allow harmless due-date/notes
    // maintenance but reject customer/tax identity changes after GST snapshot.
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
    final returnDate = DateTime.now();
    final payload = <String, dynamic>{
      'sale_id': saleId,
      'return_date': _dateOnly(returnDate),
      'items': items,
      'reason': reason.trim(),
      'location_id': origin['p_location_id'],
      'device_id': origin['p_device_id'],
    };

    final lease = await _requestIds.acquire(
      tenantId: tenantId,
      operation: 'sales_return',
      payload: payload,
      providedRequestId: requestId,
    );

    final gateway = GstV520Gateway(
      client: _supabase,
      tenantId: tenantId,
      channel: GstV520Channel.client,
      deviceId: origin['p_device_id']?.toString(),
    );
    await gateway.initialize();
    final rpc = gateway.routeFor('sales_return');

    try {
      final result = await _supabase.rpc(
        rpc,
        params: {
          'p_tenant_id': tenantId,
          'p_sale_id': saleId,
          'p_return_date': _dateOnly(returnDate),
          'p_items': items,
          'p_reason': reason.trim(),
          'p_location_id': origin['p_location_id'],
          'p_device_id': origin['p_device_id'],
          'p_request_id': lease.requestId,
        },
      );
      if (result is! Map) throw StateError('Unexpected response from $rpc.');
      await _requestIds.complete(lease);
      return Map<String, dynamic>.from(result);
    } catch (error) {
      throw StateError(
        'Authoritative GST v5.2 sales return failed. Legacy return fallback is '
        'disabled. Retry the unchanged return. $error',
      );
    }
  }

  Future<void> voidSale({
    required String tenantId,
    required String saleId,
    required String reason,
    String? requestId,
  }) async {
    final origin = await _originParams(tenantId);
    // v5.2 authoritative documents are protected by the backend immutability
    // trigger. Legacy v5.1 documents continue to use the historical void path.
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
