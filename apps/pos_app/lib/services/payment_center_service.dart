import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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

  Future<Map<String, dynamic>> receiveCustomerPayment(
    ClientSession session, {
    required String customerId,
    required double amount,
    required String paymentMethod,
    String referenceNumber = '',
    String notes = '',
  }) async {
    final locationId = LocationScopeService.currentForCreate(session);
    final result = await _supabase.rpc(
      'customer_receive_payment_v471',
      params: {
        'p_tenant_id': session.business.id,
        'p_customer_id': customerId,
        'p_amount': amount,
        'p_payment_method': paymentMethod,
        'p_reference_number': referenceNumber.trim(),
        'p_notes': notes.trim(),
        'p_sale_id': null,
        'p_location_id': locationId,
        'p_device_id': session.device?.deviceId,
        'p_request_id': const Uuid().v4(),
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected customer payment response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> paySupplier(
    ClientSession session, {
    required String supplierId,
    required double amount,
    required String paymentMethod,
    String referenceNumber = '',
    String notes = '',
  }) async {
    final locationId = LocationScopeService.currentForCreate(session);
    final result = await _supabase.rpc(
      'supplier_payment_party_v626',
      params: {
        'p_tenant_id': session.business.id,
        'p_location_id': locationId,
        'p_supplier_id': supplierId,
        'p_amount': amount,
        'p_payment_method': paymentMethod,
        'p_reference_number': referenceNumber.trim(),
        'p_notes': notes.trim(),
        'p_device_id': session.device?.deviceId,
        'p_request_id': const Uuid().v4(),
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected supplier payment response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> closeOutstanding(
    ClientSession session, {
    required String partyType,
    required String partyId,
    required String adjustmentType,
    required double amount,
    required String reason,
  }) async {
    final locationId = LocationScopeService.currentForCreate(session);
    final result = await _supabase.rpc(
      'party_outstanding_close_v626',
      params: {
        'p_tenant_id': session.business.id,
        'p_location_id': locationId,
        'p_party_type': partyType,
        'p_party_id': partyId,
        'p_adjustment_type': adjustmentType,
        'p_amount': amount,
        'p_reason': reason.trim(),
        'p_device_id': session.device?.deviceId,
        'p_request_id': const Uuid().v4(),
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected outstanding settlement response.');
    }
    return Map<String, dynamic>.from(result);
  }
}
