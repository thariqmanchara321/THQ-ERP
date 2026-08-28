import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DivisionOverviewService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> load({
    required String mainTenantId,
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _supabase.rpc(
      'division_overview_v44',
      params: {
        'p_main_tenant_id': mainTenantId,
        'p_from': DateFormat('yyyy-MM-dd').format(from),
        'p_to': DateFormat('yyyy-MM-dd').format(to),
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }
}
