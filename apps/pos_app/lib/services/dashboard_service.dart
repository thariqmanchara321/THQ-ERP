import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dashboard_data.dart';
import '../models/dashboard_insights.dart';

class DashboardService {
  SupabaseClient get _s => Supabase.instance.client;
  Future<DashboardData> load({required String tenantId}) async {
    final r = await _s.rpc(
      'dashboard_get_summary',
      params: {'p_tenant_id': tenantId},
    );
    if (r is! Map) throw Exception('Unexpected dashboard response.');
    return DashboardData.fromMap(Map<String, dynamic>.from(r));
  }

  Future<DashboardInsights> insights({required String tenantId}) async {
    final r = await _s.rpc(
      'dashboard_v3_insights',
      params: {'p_tenant_id': tenantId},
    );
    if (r is! Map) throw Exception('Unexpected insights response.');
    return DashboardInsights.fromMap(Map<String, dynamic>.from(r));
  }
}
