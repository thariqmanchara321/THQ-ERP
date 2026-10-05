import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/inventory_report.dart';
import '../models/report_document.dart';

class InventoryReportService {
  Future<List<ReportDefinition>> catalog(String tenantId) async {
    final data = await Supabase.instance.client.rpc(
      'inventory_reports_catalog_v635',
      params: {'p_tenant_id': tenantId},
    );
    if (data is! List) {
      throw StateError('Inventory Reports is unavailable.');
    }
    return reportMaps(data).map(ReportDefinition.fromMap).toList();
  }

  Future<InventoryReportResult> run(InventoryReportRequest request) async {
    final data = await Supabase.instance.client.rpc(
      'inventory_reports_run_v635',
      params: request.parameters,
    );
    if (data is! Map) {
      throw StateError('The server returned an invalid inventory report.');
    }
    return InventoryReportResult(reportMap(data));
  }
}
