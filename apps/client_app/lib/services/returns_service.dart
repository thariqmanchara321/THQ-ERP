import 'package:supabase_flutter/supabase_flutter.dart';

class ReturnsService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> register({
    required String tenantId,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String type = 'all',
    String query = '',
  }) async {
    final result = await _supabase.rpc(
      'returns_register_v45',
      params: {
        'p_tenant_id': tenantId,
        'p_from': _date(from),
        'p_to': _date(to),
        'p_location_id': locationId,
        'p_type': type,
        'p_query': query.trim().isEmpty ? null : query.trim(),
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
