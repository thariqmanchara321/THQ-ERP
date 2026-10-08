import 'package:intl/intl.dart';

import 'client_session.dart';
import 'record_presentation.dart';
import 'report_document.dart';

bool canOpenInventoryReports(ClientSession s) =>
    !s.subscription.blocksAccess &&
    s.hasModule('inventory') &&
    s.hasModule('reports') &&
    s.isEntitled('inventory') &&
    s.isEntitled('reports') &&
    s.deviceAllows('inventory') &&
    s.deviceAllows('reports') &&
    (s.hasRole('owner') || s.hasPermission('inventory.view')) &&
    (s.hasRole('owner') || s.hasPermission('reports.view'));

class InventoryReportRequest {
  final String tenantId, key, query;
  final DateTime from, to;
  final String? locationId, sortKey;
  final int offset, limit, days, expiryDays;
  final bool sortDescending;
  final Map<String, String> filters;
  InventoryReportRequest({
    required this.tenantId,
    required this.key,
    required this.from,
    required this.to,
    this.locationId,
    this.query = '',
    this.offset = 0,
    this.limit = 50,
    this.days = 30,
    this.expiryDays = 30,
    this.sortKey,
    this.sortDescending = false,
    Map<String, String> filters = const {},
  }) : filters = Map.unmodifiable(filters);
  InventoryReportRequest forExport() => InventoryReportRequest(
    tenantId: tenantId,
    key: key,
    from: from,
    to: to,
    locationId: locationId,
    query: query,
    limit: 0,
    days: days,
    expiryDays: expiryDays,
    sortKey: sortKey,
    sortDescending: sortDescending,
    filters: filters,
  );
  Map<String, dynamic> get parameters => {
    'p_tenant_id': tenantId,
    'p_request': {
      'key': key,
      'from': DateFormat('yyyy-MM-dd').format(from),
      'to': DateFormat('yyyy-MM-dd').format(to),
      'location_id': locationId,
      'query': query,
      'offset': offset,
      'limit': limit,
      'days': days,
      'expiry_days': expiryDays,
      'filters': filters,
      'sort_key': sortKey,
      'sort_desc': sortDescending,
    },
  };
}

class InventoryReportResult {
  final ReportDocument document;
  final List<Map<String, dynamic>> units;
  InventoryReportResult(Map<String, dynamic> map)
    : document = ReportDocument.fromMap(map),
      units = reportMaps(map['unit_totals']) {
    if (map['rows'] is! List ||
        document.columns.isEmpty ||
        document.definition.key.isEmpty ||
        document.totalRows < document.rows.length ||
        (document.complete &&
            (document.offset != 0 ||
                document.rows.length != document.totalRows))) {
      throw StateError(
        'The inventory report is incomplete or invalid. Refresh it.',
      );
    }
  }
  ReportDocument get presentation {
    final map = Map<String, dynamic>.from(
      RecordPresentation.clean(document.data) as Map,
    );
    final def = reportMap(map['definition']);
    def['description'] =
        '${def['description']} ${document.context['quantity_basis']} '
        'Activity lookback: ${document.context['lookback_days']} days. Expiry horizon: ${document.context['expiry_days']} days. '
        '${document.context['stock_basis']}';
    map['definition'] = def;
    map['summary'] = [
      ...reportMaps(map['summary']),
      for (final u in units)
        for (final k in [
          'quantity',
          'available',
          'opening_quantity',
          'receipts',
          'issues',
          'closing_quantity',
        ])
          if (u[k] != null)
            {
              'key': 'unit_${u['unit_code']}_$k',
              'label': '${u['unit_code']} ${k.replaceAll('_', ' ')}',
              'value': u[k],
              'type': 'number',
            },
    ];
    return ReportDocument.fromMap(map);
  }
}
