import 'package:supabase_flutter/supabase_flutter.dart';

class TerminalDayService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> load({
    required String tenantId,
    required String deviceId,
    required DateTime day,
  }) async {
    final result = await _supabase.rpc(
      'pos_terminal_day_v473',
      params: {
        'p_tenant_id': tenantId,
        'p_device_id': deviceId,
        'p_day': _date(day),
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> searchInvoices({
    required String tenantId,
    required String deviceId,
    required DateTime day,
    String query = '',
    int limit = 200,
  }) async {
    final result = await _supabase.rpc(
      'pos_terminal_invoices_v473',
      params: {
        'p_tenant_id': tenantId,
        'p_device_id': deviceId,
        'p_day': _date(day),
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
