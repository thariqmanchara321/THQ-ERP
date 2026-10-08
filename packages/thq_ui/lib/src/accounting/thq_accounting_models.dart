Map<String, dynamic> accountingMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> accountingMaps(dynamic value) => value is List
    ? value.whereType<Map>().map(accountingMap).toList()
    : <Map<String, dynamic>>[];

/// One immutable query captured for a request, drill-down or export.
class ThqAccountingQuery {
  final String report;
  final DateTime from;
  final DateTime to;
  final String search;
  final Map<String, String> filters;
  final String? sortKey;
  final bool descending;
  final int offset;
  final int limit;
  const ThqAccountingQuery({
    required this.report,
    required this.from,
    required this.to,
    this.search = '',
    this.filters = const {},
    this.sortKey,
    this.descending = false,
    this.offset = 0,
    this.limit = 100,
  });
  ThqAccountingQuery copyWith({
    String? report,
    DateTime? from,
    DateTime? to,
    String? search,
    Map<String, String>? filters,
    String? sortKey,
    bool clearSort = false,
    bool? descending,
    int? offset,
    int? limit,
  }) => ThqAccountingQuery(
    report: report ?? this.report,
    from: from ?? this.from,
    to: to ?? this.to,
    search: search ?? this.search,
    filters: filters ?? this.filters,
    sortKey: clearSort ? null : sortKey ?? this.sortKey,
    descending: descending ?? this.descending,
    offset: offset ?? this.offset,
    limit: limit ?? this.limit,
  );
  Map<String, dynamic> parameters(String tenantId, String? locationId) => {
    'p_tenant_id': tenantId,
    'p_report': report,
    'p_from': _date(from),
    'p_to': _date(to),
    'p_location_id': locationId,
    'p_query': search,
    'p_filters': filters,
    'p_sort_key': sortKey,
    'p_sort_desc': descending,
    'p_offset': offset,
    'p_limit': limit,
  };
  static String _date(DateTime x) =>
      '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
}

class ThqAccountingColumn {
  final String key;
  final String label;
  final String type;
  const ThqAccountingColumn(this.key, this.label, this.type);
  factory ThqAccountingColumn.fromMap(Map<String, dynamic> x) =>
      ThqAccountingColumn(
        x['key'].toString(),
        x['label'].toString(),
        x['type'].toString(),
      );
  bool get numeric => type == 'money' || type == 'number';
}

class ThqAccountingResult {
  final Map<String, dynamic> data;
  ThqAccountingResult(this.data) {
    if (data['rows'] is! List ||
        data['columns'] is! List ||
        data['total_rows'] is! num) {
      throw StateError('The accounting report response is incomplete.');
    }
  }
  List<Map<String, dynamic>> get rows => accountingMaps(data['rows']);
  List<ThqAccountingColumn> get columns =>
      accountingMaps(data['columns']).map(ThqAccountingColumn.fromMap).toList();
  List<Map<String, dynamic>> get summary => accountingMaps(data['summary']);
  List<Map<String, dynamic>> get alerts => accountingMaps(data['alerts']);
  Map<String, dynamic> get options => accountingMap(data['options']);
  Map<String, dynamic> get context => accountingMap(data['context']);
  int get total => (data['total_rows'] as num).toInt();
}
