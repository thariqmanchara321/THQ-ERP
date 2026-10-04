import 'dart:convert';

import 'package:intl/intl.dart';

Map<String, dynamic> reportMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> reportMaps(dynamic value) => value is List
    ? value.whereType<Map>().map(reportMap).toList()
    : <Map<String, dynamic>>[];

class ReportColumn {
  final String key;
  final String label;
  final String type;
  final double width;
  const ReportColumn(this.key, this.label, this.type, this.width);
  factory ReportColumn.fromMap(Map<String, dynamic> map) => ReportColumn(
    map['key'].toString(),
    map['label'].toString(),
    map['type']?.toString() ?? 'text',
    (map['width'] as num?)?.toDouble() ?? 160,
  );
  bool get numeric => type == 'money' || type == 'number';
}

class ReportDefinition {
  final String key;
  final String title;
  final String category;
  final String description;
  final String basis;
  final List<ReportColumn> columns;
  const ReportDefinition({
    required this.key,
    required this.title,
    required this.category,
    required this.description,
    required this.basis,
    required this.columns,
  });
  factory ReportDefinition.fromMap(Map<String, dynamic> map) =>
      ReportDefinition(
        key: map['key'].toString(),
        title: map['title'].toString(),
        category: map['category'].toString(),
        description: map['description']?.toString() ?? '',
        basis: map['basis']?.toString() ?? 'period',
        columns: reportMaps(map['columns']).map(ReportColumn.fromMap).toList(),
      );
  String get dateBasis => switch (basis) {
    'current' => 'Current balances • velocity ends today, up to 365 days',
    'as_of' => 'Balances through the To date • period movement uses both dates',
    'expiry' => 'Current balances • dates select expiry dates',
    'period_current' =>
      'Selected load dates • payment and delivery status is current',
    _ => 'Selected document or payment dates',
  };
}

class ReportRequest {
  final String tenantId;
  final String key;
  final DateTime from;
  final DateTime to;
  final String? locationId;
  final String query;
  final int offset;
  final int limit;
  final String? sortKey;
  final bool sortDescending;
  const ReportRequest({
    required this.tenantId,
    required this.key,
    required this.from,
    required this.to,
    this.locationId,
    this.query = '',
    this.offset = 0,
    this.limit = 100,
    this.sortKey,
    this.sortDescending = false,
  });
  ReportRequest exportRequest() => ReportRequest(
    tenantId: tenantId,
    key: key,
    from: from,
    to: to,
    locationId: locationId,
    query: query,
    limit: 0,
    sortKey: sortKey,
    sortDescending: sortDescending,
  );
  Map<String, dynamic> get parameters => {
    'p_tenant_id': tenantId,
    'p_report_key': key,
    'p_from': DateFormat('yyyy-MM-dd').format(from),
    'p_to': DateFormat('yyyy-MM-dd').format(to),
    'p_location_id': locationId,
    'p_query': query,
    'p_offset': offset,
    'p_limit': limit,
    'p_sort_key': sortKey,
    'p_sort_desc': sortDescending,
  };
}

class ReportDocument {
  final Map<String, dynamic> data;
  final ReportDefinition definition;
  final List<ReportColumn> columns;
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> summary;
  final Map<String, dynamic> context;
  final int totalRows;
  final int offset;
  final bool complete;
  ReportDocument.fromMap(Map<String, dynamic> map)
    : data = map,
      definition = ReportDefinition.fromMap(reportMap(map['definition'])),
      columns = reportMaps(map['columns']).map(ReportColumn.fromMap).toList(),
      rows = reportMaps(map['rows']),
      summary = _orderedSummary(reportMaps(map['summary'])),
      context = reportMap(map['context']),
      totalRows = (map['total_rows'] as num?)?.toInt() ?? 0,
      offset = (map['offset'] as num?)?.toInt() ?? 0,
      complete = map['complete'] == true;
  static List<Map<String, dynamic>> _orderedSummary(
    List<Map<String, dynamic>> values,
  ) {
    const order = [
      'revenue',
      'cogs',
      'expenses',
      'net_profit',
      'assets',
      'liabilities',
      'equity',
      'current_earnings',
      'liabilities_and_equity',
      'difference',
    ];
    final indexed = values.asMap().entries.toList();
    int rank(MapEntry<int, Map<String, dynamic>> item) {
      final index = order.indexOf(item.value['key']?.toString() ?? '');
      return index < 0 ? order.length + item.key : index;
    }

    indexed.sort((a, b) => rank(a).compareTo(rank(b)));
    return indexed.map((e) => e.value).toList();
  }

  String get currency => context['currency']?.toString() ?? 'INR';
  String format(dynamic value, String type) {
    if (value == null) return '—';
    if (type == 'money' && value is num) {
      return NumberFormat.currency(
        name: currency,
        symbol: '$currency ',
        decimalDigits: 2,
      ).format(value);
    }
    if (type == 'number' && value is num) {
      return NumberFormat('#,##0.####').format(value);
    }
    if (type == 'date' || type == 'datetime') {
      final date = DateTime.tryParse(value.toString());
      if (date != null) {
        return type == 'date'
            ? DateFormat('dd MMM yyyy').format(date)
            : '${DateFormat('dd MMM yyyy HH:mm').format(date)}${date.isUtc ? ' UTC' : ''}';
      }
    }
    return value is Map || value is List ? jsonEncode(value) : value.toString();
  }

  String cell(Map<String, dynamic> row, ReportColumn column) {
    const states = {
      'status',
      'verification',
      'direction',
      'document_kind',
      'document_class',
      'movement_type',
      'payment_source',
      'staff_mode',
      'wage_basis',
      'trip_kind',
      'account_type',
    };
    final value = row[column.key];
    if (states.contains(column.key) && value is String) {
      return value
          .split('_')
          .map(
            (part) => part.isEmpty
                ? ''
                : '${part[0].toUpperCase()}${part.substring(1)}',
          )
          .join(' ');
    }
    return format(
      value,
      row['metric'] == 'Posted invoices' && column.key == 'amount'
          ? 'number'
          : column.type,
    );
  }

  void requireComplete() {
    if (!complete || offset != 0 || rows.length != totalRows) {
      throw StateError(
        'The export dataset is incomplete. Run the report again.',
      );
    }
  }
}
