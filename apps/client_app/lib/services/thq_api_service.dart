import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ThqApiService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<dynamic> call(ThqApiRequest request) async {
    final response = await _supabase.functions.invoke(
      'thq-api',
      body: request.toJson(),
    );
    final raw = response.data;
    if (raw is! Map) {
      throw StateError('THQ API returned an invalid response.');
    }
    final body = Map<String, dynamic>.from(raw);
    if (body['success'] != true) {
      throw StateError(body['error']?.toString() ?? 'THQ API request failed.');
    }
    return body['data'];
  }

  Future<ThqSyncVersions> syncVersions(String tenantId) async {
    final data = await call(
      ThqApiRequest(tenantId: tenantId, resource: 'sync'),
    );
    if (data is! Map) throw StateError('Invalid sync response.');
    return ThqSyncVersions.fromMap(Map<String, dynamic>.from(data));
  }
}
