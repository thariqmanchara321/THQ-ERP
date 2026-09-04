import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/client_session.dart';
import '../models/payment_pending.dart';
import 'device_installation_service.dart';
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

  Future<_PaymentOrigin> _origin(ClientSession session) async {
    final locationId = LocationScopeService.selectedLocationId.value;
    if (locationId == null || locationId.isEmpty) {
      throw StateError(
        'Select a specific store before recording a payment. All Stores is view-only.',
      );
    }
    if (!session.canAccessLocation(locationId)) {
      throw StateError('You do not have access to the selected store.');
    }

    final activation = await DeviceInstallationService().readActivation();
    String? deviceId;
    if (activation != null &&
        activation.tenantId == session.business.id &&
        activation.locationId == locationId) {
      deviceId = activation.deviceId;
    }

    return _PaymentOrigin(locationId: locationId, deviceId: deviceId);
  }

  Future<Map<String, dynamic>> receiveCustomerPayment(
    ClientSession session, {
    required String customerId,
    required double amount,
    required String paymentMethod,
    String referenceNumber = '',
    String notes = '',
  }) async {
    final origin = await _origin(session);
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
        'p_location_id': origin.locationId,
        'p_device_id': origin.deviceId,
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
    final origin = await _origin(session);
    final result = await _supabase.rpc(
      'supplier_payment_create_v490',
      params: {
        'p_tenant_id': session.business.id,
        'p_location_id': origin.locationId,
        'p_supplier_id': supplierId,
        'p_payment_date': _date(DateTime.now()),
        'p_amount': amount,
        'p_payment_method': paymentMethod,
        'p_allocations': const <Map<String, dynamic>>[],
        'p_reference_number': referenceNumber.trim(),
        'p_notes': notes.trim(),
        'p_device_id': origin.deviceId,
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected supplier payment response.');
    }
    return Map<String, dynamic>.from(result);
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class _PaymentOrigin {
  const _PaymentOrigin({required this.locationId, required this.deviceId});

  final String locationId;
  final String? deviceId;
}
