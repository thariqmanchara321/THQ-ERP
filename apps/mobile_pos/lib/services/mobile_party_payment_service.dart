import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/pos_session.dart';

class MobilePartyPaymentService {
  MobilePartyPaymentService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> summary(
    PosSession session, {
    String query = '',
  }) async {
    final raw = await _client.rpc(
      'payments_party_summary_v491',
      params: {
        'p_tenant_id': session.tenantId,
        'p_location_id': session.locationId,
        'p_query': query.trim(),
        'p_limit': 1000,
      },
    );
    if (raw is! Map) {
      throw StateError('Unexpected party payments summary response.');
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<Map<String, dynamic>> receiveCustomerPayment(
    PosSession session, {
    required String customerId,
    required double amount,
    required String paymentMethod,
    String reference = '',
    String notes = '',
  }) async {
    final raw = await _client.rpc(
      'customer_receive_payment_v471',
      params: {
        'p_tenant_id': session.tenantId,
        'p_customer_id': customerId,
        'p_amount': amount,
        'p_payment_method': paymentMethod,
        'p_reference_number': reference.trim(),
        'p_notes': notes.trim(),
        'p_sale_id': null,
        'p_location_id': session.locationId,
        'p_device_id': session.deviceId,
        'p_request_id': const Uuid().v4(),
      },
    );
    return _asMap(raw, 'customer payment');
  }

  Future<Map<String, dynamic>> paySupplier(
    PosSession session, {
    required String supplierId,
    required double amount,
    required String paymentMethod,
    String reference = '',
    String notes = '',
  }) async {
    final raw = await _client.rpc(
      'supplier_payment_party_v626',
      params: {
        'p_tenant_id': session.tenantId,
        'p_location_id': session.locationId,
        'p_supplier_id': supplierId,
        'p_amount': amount,
        'p_payment_method': paymentMethod,
        'p_reference_number': reference.trim(),
        'p_notes': notes.trim(),
        'p_device_id': session.deviceId,
        'p_request_id': const Uuid().v4(),
      },
    );
    return _asMap(raw, 'supplier payment');
  }

  Future<Map<String, dynamic>> closeOutstanding(
    PosSession session, {
    required String partyType,
    required String partyId,
    required String adjustmentType,
    required double amount,
    required String reason,
  }) async {
    final raw = await _client.rpc(
      'party_outstanding_close_v626',
      params: {
        'p_tenant_id': session.tenantId,
        'p_location_id': session.locationId,
        'p_party_type': partyType,
        'p_party_id': partyId,
        'p_adjustment_type': adjustmentType,
        'p_amount': amount,
        'p_reason': reason.trim(),
        'p_device_id': session.deviceId,
        'p_request_id': const Uuid().v4(),
      },
    );
    return _asMap(raw, 'outstanding settlement');
  }

  Map<String, dynamic> _asMap(dynamic raw, String action) {
    if (raw is! Map) {
      throw StateError('Unexpected $action response.');
    }
    return Map<String, dynamic>.from(raw);
  }
}
