import 'package:supabase_flutter/supabase_flutter.dart';

class ReturnSearchService {
  SupabaseClient get _supabase => Supabase.instance.client;

  /// POS is an operational, current-day application. Historical invoice lookup
  /// lives in Terminal Daily, so return source search is deliberately limited to
  /// documents created today on this exact activated POS.
  Future<List<Map<String, dynamic>>> searchToday({
    required String tenantId,
    required String deviceId,
    required String type,
    String query = '',
    int limit = 200,
  }) async {
    final result = await _supabase.rpc(
      'pos_return_documents_today_v473',
      params: {
        'p_tenant_id': tenantId,
        'p_device_id': deviceId,
        'p_day': _date(DateTime.now()),
        'p_type': type,
        'p_query': query.trim(),
        'p_limit': limit,
      },
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
