import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin deterministic client for THQ ERP v6.0 Audit Intelligence RPCs.
///
/// This service never calculates accounting numbers in Flutter. All financial,
/// profitability and audit results come from the authoritative v6.0 backend.
class AuditIntelligenceService {
  AuditIntelligenceService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> riskConfig({required String tenantId}) async {
    final raw = await _client.rpc(
      'audit_risk_config_get_v600',
      params: {'p_tenant_id': tenantId},
    );
    return _map(raw);
  }

  Future<dynamic> setRiskConfig({
    required String tenantId,
    required Map<String, dynamic> config,
  }) {
    return _client.rpc(
      'audit_risk_config_set_v600',
      params: {'p_tenant_id': tenantId, 'p_config': config},
    );
  }

  Future<Map<String, dynamic>> auditCenterSummary({
    required String tenantId,
    required DateTime from,
    required DateTime to,
    String? locationId,
  }) async {
    final raw = await _client.rpc(
      'audit_center_summary_v600',
      params: {
        'p_tenant_id': tenantId,
        'p_from': _startTimestamp(from),
        'p_to': _endTimestamp(to),
        'p_location_id': locationId,
      },
    );
    return _map(raw);
  }

  Future<List<Map<String, dynamic>>> findings({
    required String tenantId,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String? severity,
    String? status,
    int limit = 300,
  }) async {
    final raw = await _client.rpc(
      'audit_findings_list_v600',
      params: {
        'p_tenant_id': tenantId,
        'p_severity': _blankToNull(severity),
        'p_status': _blankToNull(status),
        'p_from': _startTimestamp(from),
        'p_to': _endTimestamp(to),
        'p_location_id': locationId,
        'p_limit': limit,
      },
    );
    return _list(raw);
  }

  Future<Map<String, dynamic>> findingDetail({
    required String tenantId,
    required String findingId,
  }) async {
    final raw = await _client.rpc(
      'audit_finding_detail_v600',
      params: {'p_tenant_id': tenantId, 'p_finding_id': findingId},
    );
    return _map(raw);
  }

  Future<dynamic> reviewFinding({
    required String tenantId,
    required String findingId,
    required String status,
    required String note,
  }) {
    return _client.rpc(
      'audit_finding_review_v600',
      params: {
        'p_tenant_id': tenantId,
        'p_finding_id': findingId,
        'p_status': status,
        'p_note': note.trim(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> normalTransactions({
    required String tenantId,
    required DateTime from,
    required DateTime to,
    String? locationId,
    int limit = 150,
  }) async {
    final raw = await _client.rpc(
      'audit_normal_transactions_v600',
      params: {
        'p_tenant_id': tenantId,
        'p_from': _startTimestamp(from),
        'p_to': _endTimestamp(to),
        'p_location_id': locationId,
        'p_limit': limit,
      },
    );
    return _list(raw);
  }

  Future<Map<String, dynamic>> transactionExplanation({
    required String tenantId,
    required String entityType,
    required String entityId,
    int eventLimit = 200,
  }) async {
    final raw = await _client.rpc(
      'transaction_explain_v600',
      params: {
        'p_tenant_id': tenantId,
        'p_entity_type': entityType,
        'p_entity_id': entityId,
        'p_event_limit': eventLimit,
      },
    );
    return _map(raw);
  }

  Future<List<Map<String, dynamic>>> profitability({
    required String tenantId,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String? query,
    int limit = 250,
  }) async {
    final raw = await _client.rpc(
      'product_profitability_v600',
      params: {
        'p_tenant_id': tenantId,
        'p_from': _date(from),
        'p_to': _date(to),
        'p_location_id': locationId,
        'p_variant_id': null,
        'p_category_id': null,
        'p_brand_id': null,
        'p_query': _blankToNull(query),
        'p_limit': limit,
      },
    );
    return _list(raw);
  }

  Future<Map<String, dynamic>> productProfitExplanation({
    required String tenantId,
    required String variantId,
    required DateTime from,
    required DateTime to,
    String? locationId,
  }) async {
    final raw = await _client.rpc(
      'product_profit_explain_v600',
      params: {
        'p_tenant_id': tenantId,
        'p_variant_id': variantId,
        'p_from': _date(from),
        'p_to': _date(to),
        'p_location_id': locationId,
      },
    );
    return _map(raw);
  }

  Future<Map<String, dynamic>> metricExplanation({
    required String tenantId,
    required String metric,
    required DateTime from,
    required DateTime to,
    String? locationId,
    int driverLimit = 12,
  }) async {
    final raw = await _client.rpc(
      'explain_metric_v600',
      params: {
        'p_tenant_id': tenantId,
        'p_metric': metric,
        'p_from': _date(from),
        'p_to': _date(to),
        'p_location_id': locationId,
        'p_driver_limit': driverLimit,
      },
    );
    return _map(raw);
  }

  static String _date(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _startTimestamp(DateTime value) =>
      DateTime(value.year, value.month, value.day).toUtc().toIso8601String();

  static String _endTimestamp(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
    23,
    59,
    59,
    999,
  ).toUtc().toIso8601String();

  static String? _blankToNull(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static Map<String, dynamic> _map(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _list(dynamic raw) {
    if (raw is! List) {
      return const <Map<String, dynamic>>[];
    }
    return raw
        .map<Map<String, dynamic>>((entry) {
          if (entry is Map<String, dynamic>) {
            return Map<String, dynamic>.from(entry);
          }
          if (entry is Map) {
            return entry.map((key, value) => MapEntry(key.toString(), value));
          }
          return <String, dynamic>{'value': entry};
        })
        .toList(growable: false);
  }
}
