import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/report_document.dart';

class ReportsCenterService {
  Future<List<ReportDefinition>> catalog(String tenantId) async {
    final response = await Supabase.instance.client.rpc(
      'reports_center_catalog_v631',
      params: {'p_tenant_id': tenantId},
    );
    return reportMaps(response).map(ReportDefinition.fromMap).toList();
  }

  Future<ReportDocument> run(ReportRequest request) async {
    final response = await Supabase.instance.client.rpc(
      'reports_center_run_v631',
      params: request.parameters,
    );
    if (response is! Map || response['rows'] is! List) {
      throw StateError('The server returned an invalid report.');
    }
    return ReportDocument.fromMap(reportMap(response));
  }
}
