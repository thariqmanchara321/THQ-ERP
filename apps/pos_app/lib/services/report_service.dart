import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/report_summary.dart';

class ReportService {
  SupabaseClient get _supabase => Supabase.instance.client;
  Future<ReportSummary> summary({
    required String tenantId,
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _supabase.rpc(
      'reports_get_summary',
      params: {
        'p_tenant_id': tenantId,
        'p_from_date': _date(from),
        'p_to_date': _date(to),
      },
    );
    if (result is! Map) throw Exception('Unexpected report response.');
    return ReportSummary.fromMap(Map<String, dynamic>.from(result));
  }

  String _date(DateTime v) =>
      '${v.year.toString().padLeft(4, '0')}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
}
