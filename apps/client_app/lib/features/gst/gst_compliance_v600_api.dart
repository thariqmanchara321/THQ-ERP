import 'dart:convert';

import 'gst_compliance_v520_service.dart';

/// Client-side RPC adapter for THQ GST v6 compliance features.
///
/// GST calculation remains server-authoritative. Provider credentials never
/// enter Flutter. Submission RPCs fail closed until the server-side provider
/// connection is verified.
extension GstComplianceV600Api on GstComplianceV520Service {
  Future<Map<String, dynamic>> loadReturnsWorkspace({
    required String registrationId,
    required DateTime periodStart,
    String frequency = 'monthly',
  }) {
    _requireV600('returns');
    return _rpcMapV600(
      uiContract.tab('returns').requireString('workspace_rpc'),
      {
        'p_tenant_id': tenantId,
        'p_registration_id': registrationId,
        'p_period_start': _dateOnlyV600(periodStart),
        'p_frequency': frequency,
      },
    );
  }

  Future<Map<String, dynamic>> ensureReturnPeriod({
    required String registrationId,
    required DateTime periodStart,
    String frequency = 'monthly',
  }) {
    _requireV600('returns');
    return _rpcMapV600(
      uiContract.tab('returns').requireString('period_ensure_rpc'),
      {
        'p_tenant_id': tenantId,
        'p_registration_id': registrationId,
        'p_period_start': _dateOnlyV600(periodStart),
        'p_frequency': frequency,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listReturnPeriods({
    String? registrationId,
  }) async {
    _requireV600('returns');
    final raw = await _rpcV600(
      uiContract.tab('returns').requireString('period_list_rpc'),
      {
        'p_tenant_id': tenantId,
        'p_registration_id': _nullableV600(registrationId),
      },
    );
    return _asListV600(raw);
  }

  Future<Map<String, dynamic>> returnPeriodAction({
    required String periodId,
    required String action,
    String? reason,
  }) {
    _requireV600(
      action == 'lock' || action == 'unlock' ? 'period_lock' : 'submit',
    );
    return _rpcMapV600(
      uiContract.tab('returns').requireString('period_action_rpc'),
      {
        'p_tenant_id': tenantId,
        'p_period_id': periodId,
        'p_action': action,
        'p_reason': _nullableV600(reason),
      },
    );
  }

  Future<Map<String, dynamic>> loadGstr1Preview({
    required String registrationId,
    required DateTime from,
    required DateTime to,
  }) {
    _requireV600('returns');
    return _rpcMapV600(
      uiContract.tab('returns').requireString('gstr1_preview_rpc'),
      {
        'p_tenant_id': tenantId,
        'p_registration_id': registrationId,
        'p_from': _dateOnlyV600(from),
        'p_to': _dateOnlyV600(to),
      },
    );
  }

  Future<Map<String, dynamic>> loadGstr1aPreview({required String periodId}) {
    _requireV600('returns');
    return _rpcMapV600(
      uiContract.tab('returns').requireString('gstr1a_preview_rpc'),
      {'p_tenant_id': tenantId, 'p_period_id': periodId},
    );
  }

  Future<Map<String, dynamic>> loadGstr3bPreview({
    required String registrationId,
    required DateTime from,
    required DateTime to,
  }) {
    _requireV600('returns');
    return _rpcMapV600(
      uiContract.tab('returns').requireString('gstr3b_preview_rpc'),
      {
        'p_tenant_id': tenantId,
        'p_registration_id': registrationId,
        'p_from': _dateOnlyV600(from),
        'p_to': _dateOnlyV600(to),
      },
    );
  }

  Future<Map<String, dynamic>> loadGstr2bReconciliation({
    required String registrationId,
    required DateTime periodStart,
  }) {
    _requireV600('reconcile');
    return _rpcMapV600(
      uiContract.tab('returns').requireString('gstr2b_reconciliation_rpc'),
      {
        'p_tenant_id': tenantId,
        'p_registration_id': registrationId,
        'p_period_start': _dateOnlyV600(periodStart),
      },
    );
  }

  Future<Map<String, dynamic>> queueGstr1({
    required String periodId,
    required String requestId,
  }) {
    _requireV600('submit');
    return _queueReturn('gstr1_submit_rpc', periodId, requestId);
  }

  Future<Map<String, dynamic>> queueGstr3b({
    required String periodId,
    required String requestId,
  }) {
    _requireV600('submit');
    return _queueReturn('gstr3b_submit_rpc', periodId, requestId);
  }

  Future<Map<String, dynamic>> queueGstr2bFetch({
    required String periodId,
    required String requestId,
  }) {
    _requireV600('reconcile');
    return _queueReturn('gstr2b_fetch_rpc', periodId, requestId);
  }

  Future<Map<String, dynamic>> queueImsFetch({
    required String periodId,
    required String requestId,
  }) {
    _requireV600('reconcile');
    return _queueReturn('ims_fetch_rpc', periodId, requestId);
  }

  Future<Map<String, dynamic>> loadTurnoverProfile({DateTime? date}) {
    _requireV600('view');
    return _rpcMapV600(
      uiContract.tab('returns').requireString('turnover_get_rpc'),
      {
        'p_tenant_id': tenantId,
        'p_document_date': _dateOnlyV600(date ?? DateTime.now()),
      },
    );
  }

  Future<Map<String, dynamic>> providerConnectionStatus({
    String? registrationId,
  }) {
    _requireV600('view');
    final rpc = uiContract
        .tab('einvoice')
        .requireString('connection_status_rpc');
    return _rpcMapV600(rpc, {
      'p_tenant_id': tenantId,
      'p_registration_id': _nullableV600(registrationId),
    });
  }

  Future<Map<String, dynamic>> loadEinvoicePreview({
    required String snapshotId,
  }) {
    _requireV600('einvoice');
    return _rpcMapV600(
      uiContract.tab('einvoice').requireString('preview_rpc'),
      {'p_tenant_id': tenantId, 'p_snapshot_id': snapshotId},
    );
  }

  Future<Map<String, dynamic>> queueEinvoice({
    required String snapshotId,
    required String requestId,
  }) {
    _requireV600('einvoice');
    return _rpcMapV600(uiContract.tab('einvoice').requireString('queue_rpc'), {
      'p_tenant_id': tenantId,
      'p_snapshot_id': snapshotId,
      'p_request_id': requestId,
    });
  }

  Future<Map<String, dynamic>> loadProviderStatus({
    required String snapshotId,
  }) {
    _requireV600('view');
    return _rpcMapV600(uiContract.tab('einvoice').requireString('status_rpc'), {
      'p_tenant_id': tenantId,
      'p_snapshot_id': snapshotId,
    });
  }

  Future<Map<String, dynamic>> cancelIrnV600({
    required String snapshotId,
    required String requestId,
    required String reasonCode,
    required String remarks,
  }) {
    _requireV600('cancel_irn');
    return _rpcMapV600(uiContract.tab('einvoice').requireString('cancel_rpc'), {
      'p_tenant_id': tenantId,
      'p_snapshot_id': snapshotId,
      'p_request_id': requestId,
      'p_reason_code': reasonCode,
      'p_remarks': remarks,
    });
  }

  Future<Map<String, dynamic>> loadEwaybillPreview({
    required String snapshotId,
    Map<String, dynamic> transport = const {},
  }) {
    _requireV600('ewaybill');
    return _rpcMapV600(
      uiContract.tab('ewaybill').requireString('preview_rpc'),
      {
        'p_tenant_id': tenantId,
        'p_snapshot_id': snapshotId,
        'p_transport': transport,
      },
    );
  }

  Future<Map<String, dynamic>> queueEwaybill({
    required String snapshotId,
    required String requestId,
    Map<String, dynamic> transport = const {},
  }) {
    _requireV600('ewaybill');
    return _rpcMapV600(uiContract.tab('ewaybill').requireString('queue_rpc'), {
      'p_tenant_id': tenantId,
      'p_snapshot_id': snapshotId,
      'p_request_id': requestId,
      'p_transport': transport,
    });
  }

  Future<Map<String, dynamic>> cancelEwaybill({
    required String snapshotId,
    required String requestId,
    required String reasonCode,
    required String remarks,
  }) {
    _requireV600('ewaybill');
    return _rpcMapV600(uiContract.tab('ewaybill').requireString('cancel_rpc'), {
      'p_tenant_id': tenantId,
      'p_snapshot_id': snapshotId,
      'p_request_id': requestId,
      'p_reason_code': reasonCode,
      'p_remarks': remarks,
    });
  }

  Future<Map<String, dynamic>> retryProviderJob({required String jobId}) {
    _requireV600('submit');
    return _rpcMapV600(uiContract.tab('einvoice').requireString('retry_rpc'), {
      'p_tenant_id': tenantId,
      'p_job_id': jobId,
    });
  }

  Future<Map<String, dynamic>> _queueReturn(
    String rpcKey,
    String periodId,
    String requestId,
  ) {
    return _rpcMapV600(uiContract.tab('returns').requireString(rpcKey), {
      'p_tenant_id': tenantId,
      'p_period_id': periodId,
      'p_request_id': requestId,
    });
  }

  void _requireV600(String capability) {
    if (!isInitialized) {
      throw const GstComplianceV520Exception(
        'GST & Compliance is not initialized.',
      );
    }
    if (!can(capability)) {
      throw GstComplianceV520Exception(
        'GST permission "$capability" is required.',
      );
    }
  }

  Future<dynamic> _rpcV600(String rpc, Map<String, dynamic> params) async {
    if (!rpc.startsWith('gst_') || !rpc.endsWith('_v600')) {
      throw GstComplianceV520Exception('Unapproved GST v6 RPC "$rpc".');
    }
    try {
      return await client.rpc(rpc, params: params);
    } catch (error) {
      throw GstComplianceV520Exception('GST v6 RPC "$rpc" failed: $error');
    }
  }

  Future<Map<String, dynamic>> _rpcMapV600(
    String rpc,
    Map<String, dynamic> params,
  ) async {
    final raw = await _rpcV600(rpc, params);
    return _asMapV600(raw, rpc);
  }
}

Map<String, dynamic> _asMapV600(dynamic raw, String rpc) {
  dynamic value = raw;
  if (value is String) value = jsonDecode(value);
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw GstComplianceV520Exception(
    'Expected JSON object from "$rpc", got ${value.runtimeType}.',
  );
}

List<Map<String, dynamic>> _asListV600(dynamic raw) {
  dynamic value = raw;
  if (value is String) value = jsonDecode(value);
  if (value is Map && value['periods'] is List) {
    value = value['periods'];
  }
  if (value is! List) {
    throw GstComplianceV520Exception(
      'Expected JSON list from GST v6 period RPC, got ${value.runtimeType}.',
    );
  }
  return value
      .whereType<Map>()
      .map(
        (entry) => entry.map((key, value) => MapEntry(key.toString(), value)),
      )
      .toList(growable: false);
}

String _dateOnlyV600(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String? _nullableV600(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}
