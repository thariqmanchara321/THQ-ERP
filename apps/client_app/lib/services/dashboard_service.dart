import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import '../models/dashboard_data.dart';
import '../models/dashboard_insights.dart';
import 'location_scope_service.dart';

class DashboardService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<DashboardData> load({required ClientSession session}) async {
    final result = await _supabase.rpc(
      'dashboard_get_summary_v4',
      params: {
        'p_tenant_id': session.business.id,
        'p_location_id': LocationScopeService.currentForRead(session),
      },
    );
    if (result is! Map) throw Exception('Unexpected dashboard response.');
    return DashboardData.fromMap(Map<String, dynamic>.from(result));
  }

  Future<DashboardInsights> insights({required ClientSession session}) async {
    final result = await _supabase.rpc(
      'dashboard_v3_insights_v32',
      params: {
        'p_tenant_id': session.business.id,
        'p_location_id': LocationScopeService.currentForRead(session),
      },
    );
    if (result is! Map) throw Exception('Unexpected insights response.');
    return DashboardInsights.fromMap(Map<String, dynamic>.from(result));
  }
}
