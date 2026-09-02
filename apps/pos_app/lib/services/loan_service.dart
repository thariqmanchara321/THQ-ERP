import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import 'location_scope_service.dart';
import 'thq_api_service.dart';

class LoanService {
  final ThqApiService _api = ThqApiService();
  SupabaseClient get _supabase => Supabase.instance.client;

  String? _readLocation(ClientSession session) =>
      LocationScopeService.current(session);

  String _writeLocation(ClientSession session) {
    final location = LocationScopeService.current(session);
    if (location == null || location.isEmpty) {
      throw StateError('This POS terminal is not assigned to a location.');
    }
    return location;
  }

  List<Map<String, dynamic>> _rows(dynamic data) => (data as List? ?? const [])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);

  Map<String, dynamic> _map(dynamic data) =>
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

  bool _isReadOnly(ThqApiRequest request) =>
      request.resource == 'loan-dashboard' ||
      request.resource == 'loan-warnings' ||
      request.resource == 'customer-loans' ||
      (request.resource == 'loans' &&
          (request.action == 'list' ||
              request.action == 'detail' ||
              request.action == 'settings-get'));

  bool _isCompatibilityFailure(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('unknown thq api resource') ||
        message.contains('unsupported ') ||
        message.contains('function not found') ||
        message.contains('status: 400') ||
        message.contains('bad request') ||
        message.contains('404');
  }

  /// API-first with an authenticated RPC fallback. Mutations only retry when
  /// the edge contract is clearly stale/missing, avoiding duplicate financial
  /// transactions after an ambiguous network response failure.
  Future<dynamic> _call(ThqApiRequest request) async {
    try {
      return await _api.call(request);
    } catch (apiError) {
      if (!_isReadOnly(request) && !_isCompatibilityFailure(apiError)) {
        rethrow;
      }
      try {
        return await _rpcFallback(request);
      } catch (rpcError) {
        throw StateError(
          'Loan request failed through THQ API ($apiError) and RPC fallback ($rpcError).',
        );
      }
    }
  }

  Future<dynamic> _rpcFallback(ThqApiRequest request) {
    final p = request.payload;
    final base = <String, dynamic>{'p_tenant_id': request.tenantId};
    late String rpc;
    late Map<String, dynamic> params;

    switch (request.resource) {
      case 'loans':
        switch (request.action) {
          case 'list':
            rpc = 'loan_list_v491';
            params = {
              ...base,
              'p_location_id': p['location_id'],
              'p_status': p['status'],
              'p_direction': p['direction'],
              'p_query': p['query'] ?? '',
              'p_limit': p['limit'] ?? 500,
            };
          case 'detail':
            rpc = 'loan_detail_v491';
            params = {...base, 'p_loan_id': p['loan_id']};
          case 'create':
            rpc = 'loan_create_v491';
            params = {
              ...base,
              'p_location_id': p['location_id'],
              'p_payload': p['loan'] ?? <String, dynamic>{},
            };
          case 'update':
            rpc = 'loan_update_v491';
            params = {
              ...base,
              'p_loan_id': p['loan_id'],
              'p_payload': p['loan'] ?? <String, dynamic>{},
            };
          case 'submit':
            rpc = 'loan_submit_v490';
            params = {...base, 'p_loan_id': p['loan_id']};
          case 'decide':
            rpc = 'loan_decide_v490';
            params = {
              ...base,
              'p_loan_id': p['loan_id'],
              'p_approve': p['approve'] ?? false,
              'p_note': p['note'] ?? '',
            };
          case 'disburse':
            rpc = 'loan_activate_v491';
            params = {
              ...base,
              'p_loan_id': p['loan_id'],
              'p_disbursement_date': p['disbursement_date'],
              'p_payment_method': p['payment_method'] ?? 'bank',
              'p_reference_number': p['reference_number'] ?? '',
              'p_device_id': p['device_id'],
            };
          case 'payment':
            rpc = 'loan_payment_create_v491';
            params = {
              ...base,
              'p_loan_id': p['loan_id'],
              'p_amount': p['amount'],
              'p_payment_date': p['payment_date'],
              'p_payment_method': p['payment_method'] ?? 'cash',
              'p_reference_number': p['reference_number'] ?? '',
              'p_notes': p['notes'] ?? '',
              'p_device_id': p['device_id'],
            };
          case 'payment-reverse':
            rpc = 'loan_payment_reverse_v491';
            params = {
              ...base,
              'p_payment_id': p['payment_id'],
              'p_reason': p['reason'] ?? '',
            };
          case 'rate-change':
            rpc = 'loan_rate_change_v490';
            params = {
              ...base,
              'p_loan_id': p['loan_id'],
              'p_new_rate': p['new_rate'],
              'p_effective_date': p['effective_date'],
              'p_rate_index': p['rate_index'],
              'p_rate_margin': p['rate_margin'],
              'p_reason': p['reason'] ?? '',
            };
          case 'status':
            rpc = 'loan_status_v490';
            params = {
              ...base,
              'p_loan_id': p['loan_id'],
              'p_status': p['status'],
              'p_reason': p['reason'] ?? '',
            };
          case 'collateral-save':
            rpc = 'loan_collateral_save_v490';
            params = {
              ...base,
              'p_loan_id': p['loan_id'],
              'p_collateral_id': p['collateral_id'],
              'p_type': p['type'],
              'p_description': p['description'],
              'p_reference_number': p['reference_number'] ?? '',
              'p_estimated_value': p['estimated_value'] ?? 0,
              'p_status': p['status'] ?? 'active',
              'p_notes': p['notes'] ?? '',
            };
          case 'guarantor-save':
            rpc = 'loan_guarantor_save_v490';
            params = {
              ...base,
              'p_loan_id': p['loan_id'],
              'p_guarantor_id': p['guarantor_id'],
              'p_customer_id': p['customer_id'],
              'p_name': p['name'],
              'p_phone': p['phone'] ?? '',
              'p_email': p['email'] ?? '',
              'p_guarantee_amount': p['guarantee_amount'],
              'p_notes': p['notes'] ?? '',
            };
          case 'settings-get':
            rpc = 'loan_settings_v491_get';
            params = base;
          case 'settings-set':
            rpc = 'loan_settings_v491_set';
            params = {...base, 'p_reflect': p['reflect_in_accounting'] ?? true};
          default:
            throw UnsupportedError(
              'Unsupported loans action ${request.action}.',
            );
        }
      case 'loan-dashboard':
        rpc = 'loan_dashboard_v491';
        params = {...base, 'p_location_id': p['location_id']};
      case 'loan-warnings':
        rpc = 'loan_warnings_v491';
        params = {
          ...base,
          'p_location_id': p['location_id'],
          'p_limit': p['limit'] ?? 250,
        };
      case 'customer-loans':
        rpc = 'customer_loan_summary_v490';
        params = {...base, 'p_customer_id': p['customer_id']};
      default:
        throw UnsupportedError('No loan RPC fallback for ${request.resource}.');
    }
    return _supabase.rpc(rpc, params: params);
  }

  Future<List<Map<String, dynamic>>> list(
    ClientSession session, {
    String? status,
    String? direction,
    String query = '',
  }) async => _rows(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loans',
        action: 'list',
        payload: {
          'location_id': _readLocation(session),
          'status': status,
          'direction': direction,
          'query': query,
          'limit': 1000,
        },
      ),
    ),
  );

  Future<Map<String, dynamic>> dashboard(ClientSession session) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loan-dashboard',
        payload: {'location_id': _readLocation(session)},
      ),
    ),
  );

  Future<List<Map<String, dynamic>>> warnings(ClientSession session) async =>
      _rows(
        await _call(
          ThqApiRequest(
            tenantId: session.business.id,
            resource: 'loan-warnings',
            payload: {'location_id': _readLocation(session), 'limit': 250},
          ),
        ),
      );

  Future<Map<String, dynamic>> detail(
    ClientSession session,
    String loanId,
  ) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loans',
        action: 'detail',
        payload: {'loan_id': loanId},
      ),
    ),
  );

  Future<Map<String, dynamic>> create(
    ClientSession session,
    Map<String, dynamic> loan,
  ) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loans',
        action: 'create',
        payload: {'location_id': _writeLocation(session), 'loan': loan},
      ),
    ),
  );

  Future<Map<String, dynamic>> update(
    ClientSession session,
    String loanId,
    Map<String, dynamic> loan,
  ) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loans',
        action: 'update',
        payload: {'loan_id': loanId, 'loan': loan},
      ),
    ),
  );

  Future<void> submit(ClientSession session, String loanId) async {
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loans',
        action: 'submit',
        payload: {'loan_id': loanId},
      ),
    );
  }

  Future<void> decide(
    ClientSession session,
    String loanId, {
    required bool approve,
    String note = '',
  }) async {
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loans',
        action: 'decide',
        payload: {'loan_id': loanId, 'approve': approve, 'note': note},
      ),
    );
  }

  Future<void> disburse(
    ClientSession session,
    String loanId, {
    required DateTime date,
    required String paymentMethod,
    String referenceNumber = '',
  }) async {
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loans',
        action: 'disburse',
        payload: {
          'loan_id': loanId,
          'disbursement_date': date.toIso8601String().split('T').first,
          'payment_method': paymentMethod,
          'reference_number': referenceNumber,
          'device_id': session.device?.deviceId,
        },
      ),
    );
  }

  Future<Map<String, dynamic>> collect(
    ClientSession session,
    String loanId, {
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String referenceNumber = '',
    String notes = '',
  }) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loans',
        action: 'payment',
        payload: {
          'loan_id': loanId,
          'amount': amount,
          'payment_date': date.toIso8601String().split('T').first,
          'payment_method': paymentMethod,
          'reference_number': referenceNumber,
          'notes': notes,
          'device_id': session.device?.deviceId,
        },
      ),
    ),
  );

  Future<void> reversePayment(
    ClientSession session,
    String paymentId,
    String reason,
  ) async {
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loans',
        action: 'payment-reverse',
        payload: {'payment_id': paymentId, 'reason': reason},
      ),
    );
  }

  Future<void> changeRate(
    ClientSession session,
    String loanId, {
    required double newRate,
    required DateTime effectiveDate,
    String? rateIndex,
    double? rateMargin,
    String reason = '',
  }) async {
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loans',
        action: 'rate-change',
        payload: {
          'loan_id': loanId,
          'new_rate': newRate,
          'effective_date': effectiveDate.toIso8601String().split('T').first,
          'rate_index': rateIndex,
          'rate_margin': rateMargin,
          'reason': reason,
        },
      ),
    );
  }

  Future<void> setStatus(
    ClientSession session,
    String loanId,
    String status, {
    String reason = '',
  }) async {
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loans',
        action: 'status',
        payload: {'loan_id': loanId, 'status': status, 'reason': reason},
      ),
    );
  }

  Future<String> saveCollateral(
    ClientSession session,
    String loanId, {
    String? collateralId,
    required String type,
    required String description,
    String referenceNumber = '',
    double estimatedValue = 0,
    String status = 'active',
    String notes = '',
  }) async {
    final value = await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loans',
        action: 'collateral-save',
        payload: {
          'loan_id': loanId,
          'collateral_id': collateralId,
          'type': type,
          'description': description,
          'reference_number': referenceNumber,
          'estimated_value': estimatedValue,
          'status': status,
          'notes': notes,
        },
      ),
    );
    return value.toString();
  }

  Future<String> saveGuarantor(
    ClientSession session,
    String loanId, {
    String? guarantorId,
    String? customerId,
    required String name,
    String phone = '',
    String email = '',
    double? guaranteeAmount,
    String notes = '',
  }) async {
    final value = await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loans',
        action: 'guarantor-save',
        payload: {
          'loan_id': loanId,
          'guarantor_id': guarantorId,
          'customer_id': customerId,
          'name': name,
          'phone': phone,
          'email': email,
          'guarantee_amount': guaranteeAmount,
          'notes': notes,
        },
      ),
    );
    return value.toString();
  }

  Future<Map<String, dynamic>> settings(ClientSession session) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loans',
        action: 'settings-get',
      ),
    ),
  );

  Future<void> setAccountingEnabled(ClientSession session, bool enabled) async {
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'loans',
        action: 'settings-set',
        payload: {'reflect_in_accounting': enabled},
      ),
    );
  }

  Future<Map<String, dynamic>> customerSummary(
    ClientSession session,
    String customerId,
  ) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'customer-loans',
        payload: {'customer_id': customerId},
      ),
    ),
  );
}
