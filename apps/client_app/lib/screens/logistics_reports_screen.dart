import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/location_scope_service.dart';
import '../services/logistics_service.dart';

class LogisticsReportsScreen extends StatefulWidget {
  final ClientSession session;

  const LogisticsReportsScreen({super.key, required this.session});

  @override
  State<LogisticsReportsScreen> createState() => _LogisticsReportsScreenState();
}

class _LogisticsReportsScreenState extends State<LogisticsReportsScreen> {
  final LogisticsService _service = LogisticsService();

  late DateTime _fromDate;
  late DateTime _toDate;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _report = const {};

  String get _tenantId => widget.session.business.id;
  String? get _locationId =>
      LocationScopeService.currentForRead(widget.session);

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _toDate = today;
    _fromDate = today.subtract(const Duration(days: 29));
    _load();
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.reportsDashboard(
        tenantId: _tenantId,
        locationId: _locationId,
        fromDate: _fromDate,
        toDate: _toDate,
      );
      if (!mounted) {
        return;
      }
      setState(() => _report = result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = _clean(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _clean(Object error) => error
      .toString()
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('Exception: ', '');

  Map<String, dynamic> get _summary {
    final value = _report['summary'];
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  List<Map<String, dynamic>> _rows(String key) {
    final value = _report[key];
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
      helpText: 'Logistics report period',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _fromDate = _dateOnly(picked.start);
      _toDate = _dateOnly(picked.end);
    });
    await _load();
  }

  Future<void> _setPreset(int days) async {
    final today = _dateOnly(DateTime.now());
    setState(() {
      _toDate = today;
      _fromDate = today.subtract(Duration(days: days - 1));
    });
    await _load();
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _dateTime(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) {
      return value.toString();
    }
    final local = parsed.toLocal();
    return '${_date(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _qty(dynamic value) {
    if (value == null) {
      return '0';
    }
    final parsed = num.tryParse(value.toString());
    if (parsed == null) {
      return value.toString();
    }
    if (parsed == parsed.roundToDouble()) {
      return parsed.toInt().toString();
    }
    return parsed.toStringAsFixed(2).replaceFirst(RegExp(r'\.0+$'), '');
  }

  String _text(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  Widget _metric(String label, dynamic value, IconData icon) {
    return SizedBox(
      width: 154,
      height: 72,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _qty(value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range_outlined, size: 18),
                label: Text('${_date(_fromDate)}  →  ${_date(_toDate)}'),
              ),
              const SizedBox(width: 8),
              for (final days in const [7, 30, 90, 365]) ...[
                ChoiceChip(
                  label: Text('${days}D'),
                  selected: _toDate.difference(_fromDate).inDays + 1 == days,
                  onSelected: (_) => _setPreset(days),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
              ],
              const SizedBox(width: 6),
              if (_locationId != null)
                const Tooltip(
                  message:
                      'Report is scoped to the currently selected location',
                  child: Chip(
                    avatar: Icon(Icons.store_outlined, size: 16),
                    label: Text('Current location'),
                    visualDensity: VisualDensity.compact,
                  ),
                )
              else
                const Tooltip(
                  message:
                      'Report includes all locations allowed for this user',
                  child: Chip(
                    avatar: Icon(Icons.business_outlined, size: 16),
                    label: Text('Allowed locations'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryStrip() {
    final summary = _summary;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _metric('Trips', summary['total_trips'], Icons.route_outlined),
          const SizedBox(width: 8),
          _metric(
            'Documents',
            summary['documents'],
            Icons.description_outlined,
          ),
          const SizedBox(width: 8),
          _metric(
            'In Transit Qty',
            summary['stock_in_transit_quantity'],
            Icons.local_shipping_outlined,
          ),
          const SizedBox(width: 8),
          _metric(
            'Pending Receipts',
            summary['pending_receipts'],
            Icons.inventory_2_outlined,
          ),
          const SizedBox(width: 8),
          _metric(
            'Good Qty',
            summary['good_quantity'],
            Icons.check_circle_outline,
          ),
          const SizedBox(width: 8),
          _metric(
            'Variance Receipts',
            summary['variance_receipts'],
            Icons.warning_amber_outlined,
          ),
          const SizedBox(width: 8),
          _metric(
            'Damaged',
            summary['damaged_quantity'],
            Icons.broken_image_outlined,
          ),
          const SizedBox(width: 8),
          _metric('Missing', summary['missing_quantity'], Icons.help_outline),
          const SizedBox(width: 8),
          _metric(
            'Returned',
            summary['returned_quantity'],
            Icons.undo_outlined,
          ),
        ],
      ),
    );
  }

  Widget _table({
    required String emptyMessage,
    required List<Map<String, dynamic>> rows,
    required List<_ReportColumn> columns,
  }) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyMessage),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                headingRowHeight: 42,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 54,
                horizontalMargin: 12,
                columnSpacing: 22,
                columns: columns
                    .map(
                      (column) => DataColumn(
                        numeric: column.numeric,
                        label: Text(
                          column.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    )
                    .toList(),
                rows: rows
                    .map(
                      (row) => DataRow(
                        cells: columns
                            .map(
                              (column) => DataCell(
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: column.maxWidth,
                                  ),
                                  child: Text(
                                    column.dateTime
                                        ? _dateTime(row[column.key])
                                        : column.quantity
                                        ? _qty(row[column.key])
                                        : _text(row[column.key]),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tripRegister() => _table(
    emptyMessage: 'No logistics trips in this period.',
    rows: _rows('trip_register'),
    columns: const [
      _ReportColumn('Trip', 'trip_number'),
      _ReportColumn('Status', 'status'),
      _ReportColumn('From', 'from_location', maxWidth: 220),
      _ReportColumn('To', 'to_location', maxWidth: 220),
      _ReportColumn('Vehicle', 'vehicle_registration'),
      _ReportColumn('Driver', 'driver_name'),
      _ReportColumn('Docs', 'document_count', numeric: true, quantity: true),
      _ReportColumn(
        'Dispatched',
        'dispatched_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn(
        'Received',
        'received_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn(
        'Damaged',
        'damaged_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn(
        'Missing',
        'missing_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn(
        'Returned',
        'returned_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn('Dispatched At', 'dispatched_at', dateTime: true),
    ],
  );

  Widget _stockInTransit() => _table(
    emptyMessage: 'No stock is currently in transit for this period.',
    rows: _rows('stock_in_transit'),
    columns: const [
      _ReportColumn('Trip', 'trip_number'),
      _ReportColumn('Transfer', 'transfer_number'),
      _ReportColumn('From', 'from_location', maxWidth: 220),
      _ReportColumn('To', 'to_location', maxWidth: 220),
      _ReportColumn('Vehicle', 'vehicle_registration'),
      _ReportColumn('Driver', 'driver_name'),
      _ReportColumn(
        'Dispatched',
        'dispatched_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn(
        'Received',
        'received_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn(
        'Remaining',
        'remaining_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn('Dispatched At', 'dispatched_at', dateTime: true),
    ],
  );

  Widget _pendingReceipts() => _table(
    emptyMessage: 'No pending logistics receipts.',
    rows: _rows('pending_receipts'),
    columns: const [
      _ReportColumn('Trip', 'trip_number'),
      _ReportColumn('Trip Status', 'trip_status'),
      _ReportColumn('Transfer', 'transfer_number'),
      _ReportColumn('Destination', 'to_location', maxWidth: 220),
      _ReportColumn('Vehicle', 'vehicle_registration'),
      _ReportColumn(
        'Dispatched Qty',
        'dispatched_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn('Arrived At', 'arrived_at', dateTime: true),
    ],
  );

  Widget _variances() => _table(
    emptyMessage: 'No damaged, missing, or returned receipt variances.',
    rows: _rows('variances'),
    columns: const [
      _ReportColumn('Receipt', 'receipt_number'),
      _ReportColumn('Trip', 'trip_number'),
      _ReportColumn('Transfer', 'transfer_number'),
      _ReportColumn('From', 'from_location', maxWidth: 210),
      _ReportColumn('To', 'to_location', maxWidth: 210),
      _ReportColumn('Vehicle', 'vehicle_registration'),
      _ReportColumn('Good', 'good_quantity', numeric: true, quantity: true),
      _ReportColumn(
        'Damaged',
        'damaged_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn(
        'Missing',
        'missing_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn(
        'Returned',
        'returned_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn('Received At', 'received_at', dateTime: true),
      _ReportColumn('Note', 'note', maxWidth: 260),
    ],
  );

  Widget _vehicleMovement() => _table(
    emptyMessage: 'No vehicle movement in this period.',
    rows: _rows('vehicle_movement'),
    columns: const [
      _ReportColumn('Registration', 'registration_number'),
      _ReportColumn('Type', 'vehicle_type'),
      _ReportColumn('Model', 'make_model', maxWidth: 180),
      _ReportColumn('Trips', 'trips', numeric: true, quantity: true),
      _ReportColumn('Documents', 'documents', numeric: true, quantity: true),
      _ReportColumn(
        'Dispatched',
        'dispatched_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn(
        'Damaged',
        'damaged_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn(
        'Missing',
        'missing_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn(
        'Returned',
        'returned_quantity',
        numeric: true,
        quantity: true,
      ),
    ],
  );

  Widget _productMovement() => _table(
    emptyMessage: 'No received product movement in this period.',
    rows: _rows('product_movement'),
    columns: const [
      _ReportColumn('Product', 'product_name', maxWidth: 240),
      _ReportColumn('SKU', 'sku'),
      _ReportColumn('Tracking', 'tracking_mode'),
      _ReportColumn(
        'Dispatched',
        'dispatched_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn('Good', 'good_quantity', numeric: true, quantity: true),
      _ReportColumn(
        'Damaged',
        'damaged_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn(
        'Missing',
        'missing_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn(
        'Returned',
        'returned_quantity',
        numeric: true,
        quantity: true,
      ),
    ],
  );

  Widget _traceExceptions() => _table(
    emptyMessage: 'No serial or batch exceptions in this period.',
    rows: _rows('trace_exceptions'),
    columns: const [
      _ReportColumn('Trip', 'trip_number'),
      _ReportColumn('Transfer', 'transfer_number'),
      _ReportColumn('Receipt', 'receipt_number'),
      _ReportColumn('Product', 'product_name', maxWidth: 220),
      _ReportColumn('SKU', 'sku'),
      _ReportColumn('Tracking', 'tracking_mode'),
      _ReportColumn('Serial', 'serial_number'),
      _ReportColumn('Batch', 'batch_number'),
      _ReportColumn('Outcome', 'outcome'),
      _ReportColumn('Qty', 'quantity', numeric: true, quantity: true),
      _ReportColumn(
        'Damaged',
        'damaged_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn(
        'Missing',
        'missing_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn(
        'Returned',
        'returned_quantity',
        numeric: true,
        quantity: true,
      ),
      _ReportColumn('Received At', 'received_at', dateTime: true),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vehicle Logistics Reports'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh reports',
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            children: [
              _filters(),
              const SizedBox(height: 8),
              _summaryStrip(),
              const SizedBox(height: 8),
              const Material(
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Trips'),
                    Tab(text: 'In Transit'),
                    Tab(text: 'Pending'),
                    Tab(text: 'Variances'),
                    Tab(text: 'Vehicles'),
                    Tab(text: 'Products'),
                    Tab(text: 'Serial / Batch'),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 36),
                            const SizedBox(height: 8),
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : TabBarView(
                        children: [
                          _tripRegister(),
                          _stockInTransit(),
                          _pendingReceipts(),
                          _variances(),
                          _vehicleMovement(),
                          _productMovement(),
                          _traceExceptions(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportColumn {
  final String label;
  final String key;
  final bool numeric;
  final bool quantity;
  final bool dateTime;
  final double maxWidth;

  const _ReportColumn(
    this.label,
    this.key, {
    this.numeric = false,
    this.quantity = false,
    this.dateTime = false,
    this.maxWidth = 170,
  });
}
