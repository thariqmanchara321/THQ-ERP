import 'package:supabase_flutter/supabase_flutter.dart';

class TransportTripHubService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> list({
    required String tenantId,
    String? locationId,
    String? kind,
    String? query,
    int limit = 500,
  }) async {
    final result = await _db.rpc(
      'transport_trip_hub_list_v611',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_kind': kind,
        'p_query': query,
        'p_limit': limit,
      },
    );

    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, dynamic>> context({
    required String tenantId,
    required String sourceType,
    required String sourceId,
  }) async {
    final result = await _db.rpc(
      'transport_trip_hub_context_v611',
      params: {
        'p_tenant_id': tenantId,
        'p_source_type': sourceType,
        'p_source_id': sourceId,
      },
    );

    if (result is! Map) {
      throw StateError('Unexpected Transport Trip Hub context response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> link({
    required String tenantId,
    required String primarySourceType,
    required String primarySourceId,
    required String secondarySourceType,
    required String secondarySourceId,
  }) async {
    final result = await _db.rpc(
      'transport_trip_hub_link_v611',
      params: {
        'p_tenant_id': tenantId,
        'p_primary_source_type': primarySourceType,
        'p_primary_source_id': primarySourceId,
        'p_secondary_source_type': secondarySourceType,
        'p_secondary_source_id': secondarySourceId,
      },
    );

    if (result is! Map) {
      throw StateError('Unexpected Transport Trip Hub link response.');
    }
    return Map<String, dynamic>.from(result);
  }
}
