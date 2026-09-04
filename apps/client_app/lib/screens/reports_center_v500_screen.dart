import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import '../services/location_scope_service.dart';

class ReportsCenterV500Screen extends StatefulWidget {
  final ClientSession session;
  const ReportsCenterV500Screen({super.key, required this.session});

  @override
  State<ReportsCenterV500Screen> createState() =>
      _ReportsCenterV500ScreenState();
}

class _ReportsCenterV500ScreenState extends State<ReportsCenterV500Screen> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _catalog = const [];
  List<Map<String, dynamic>> _rows = const [];
  List<String> _columnsCache = const [];
  Map<String, String> _reportNameByKey = const {};
  int _runGeneration = 0;
  String? _reportKey;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  bool _loading = true;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _maps(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList()
      : const <Map<String, dynamic>>[];

  static const Map<String, String> _reportNames = {
    'sales_summary': 'Sales Summary',
    'sales_register': 'Sales Register',
    'sales_by_product': 'Sales by Product',
    'sales_by_customer': 'Sales by Customer',
    'sales_by_salesperson': 'Sales by Salesperson',
    'sales_by_store': 'Sales by Store',
    'sales_by_pos': 'Sales by POS',
    'sales_by_payment_method': 'Sales by Payment Method',
    'returns': 'Returns',
    'current_stock': 'Current Stock',
    'stock_valuation': 'Stock Valuation',
    'stock_movement': 'Stock Movement',
    'stock_aging': 'Stock Aging',
    'expiry': 'Expiry',
    'dead_stock': 'Dead Stock',
    'low_stock': 'Low Stock',
    'serials': 'Serial Numbers',
    'batches': 'Batch / Lot',
    'purchase_register': 'Purchase Register',
    'supplier_purchase': 'Supplier Purchases',
    'purchase_returns': 'Purchase Returns',
    'supplier_outstanding': 'Supplier Outstanding',
    'supplier_performance': 'Supplier Performance',
    'price_history': 'Purchase Price History',
    'profit_loss': 'Profit & Loss',
    'balance_sheet': 'Balance Sheet',
    'trial_balance': 'Trial Balance',
    'general_ledger': 'General Ledger',
    'cash_flow': 'Cash Flow',
    'receivables': 'Accounts Receivable',
    'payables': 'Accounts Payable',
    'journal_register': 'Journal Register',
    'expenses': 'Expense Register',
    'tax': 'GST / Tax Report',
    'reconciliation': 'Financial Reconciliation',
  };

  List<Map<String, dynamic>> _flattenCatalog(dynamic raw) {
    final out = <Map<String, dynamic>>[];
    for (final group in _maps(raw)) {
      final category = group['category']?.toString() ?? 'Reports';
      final reports = group['reports'];
      if (reports is! List) continue;
      for (final item in reports) {
        final key = item?.toString().trim() ?? '';
        if (key.isEmpty) continue;
        out.add({
          'category': category,
          'key': key,
          'name': _reportNames[key] ?? _label(key),
        });
      }
    }
    return out;
  }

  String _date(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _initialize() async {
    try {
      final raw = await Supabase.instance.client.rpc('reports_catalog_v500');
      _catalog = _flattenCatalog(raw);
      _reportNameByKey = Map<String, String>.unmodifiable({
        for (final report in _catalog)
          if ((report['key']?.toString() ?? '').isNotEmpty)
            report['key'].toString():
                report['name']?.toString() ?? report['key'].toString(),
      });
      _reportKey = _catalog.isEmpty
          ? 'sales_summary'
          : _catalog.first['key']?.toString();
      await _run();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _invalidateResult() {
    _runGeneration++;
    _rows = const [];
    _columnsCache = const [];
    _error = null;
    _loading = false;
  }

  List<String> _deriveColumns(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const [];
    final columns = <String>[];
    for (final row in rows.take(50)) {
      for (final key in row.keys) {
        if (!columns.contains(key)) columns.add(key);
      }
    }
    return List<String>.unmodifiable(columns);
  }

  Future<void> _run() async {
    final key = _reportKey;
    if (key == null) return;

    final request = ++_runGeneration;
    final from = _from;
    final to = _to;
    final locationId = LocationScopeService.currentForRead(widget.session);
    final query = _query.text.trim();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final raw = await Supabase.instance.client.rpc(
        'reports_center_data_v500',
        params: {
          'p_tenant_id': widget.session.business.id,
          'p_report_key': key,
          'p_from': _date(from),
          'p_to': _date(to),
          'p_location_id': locationId,
          'p_query': query,
          'p_limit': 5000,
        },
      );
      final rows = _maps(raw);
      final columns = _deriveColumns(rows);

      if (!mounted || request != _runGeneration) return;
      setState(() {
        _rows = rows;
        _columnsCache = columns;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || request != _runGeneration) return;
      setState(() {
        _error = e.toString();
        _rows = const [];
        _columnsCache = const [];
        _loading = false;
      });
    }
  }

  Future<void> _pickDate(bool from) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = picked;
      } else {
        _to = picked;
      }
      if (_from.isAfter(_to)) {
        final swap = _from;
        _from = _to;
        _to = swap;
      }
      _invalidateResult();
    });
  }

  List<String> get _columns => _columnsCache;

  String get _reportTitle =>
      _reportNameByKey[_reportKey] ?? _reportKey ?? 'Report';

  Future<Uint8List> _pdf() async {
    final document = pw.Document();
    final columns = _columns.take(8).toList();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(22),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              widget.session.business.name,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              '$_reportTitle • ${_date(_from)} to ${_date(_to)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (_) => [
          if (_rows.isEmpty)
            pw.Text('No records')
          else
            pw.TableHelper.fromTextArray(
              headers: columns.map(_label).toList(),
              data: _rows
                  .map((r) => columns.map((c) => _cell(r[c])).toList())
                  .toList(),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headerStyle: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 6.5),
            ),
        ],
        footer: (c) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${c.pageNumber} of ${c.pagesCount}',
            style: const pw.TextStyle(fontSize: 7),
          ),
        ),
      ),
    );
    return document.save();
  }

  Future<void> _export(String type) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final safe = _reportTitle.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final name = 'THQ_${safe}_${_date(_from)}_${_date(_to)}';
      if (type == 'xlsx') {
        final excel = Excel.createExcel();
        final sheet = excel['Report'];
        final columns = _columns;
        sheet.appendRow(columns.map((x) => TextCellValue(_label(x))).toList());
        for (final row in _rows) {
          sheet.appendRow(
            columns.map((x) => TextCellValue(_cell(row[x]))).toList(),
          );
        }
        final raw = excel.save();
        if (raw == null) throw Exception('Could not create Excel report.');
        await FileSaver.instance.saveFile(
          name: name,
          bytes: Uint8List.fromList(raw),
          fileExtension: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
      } else {
        final bytes = await _pdf();
        if (type == 'print') {
          await Printing.layoutPdf(
            name: '$name.pdf',
            onLayout: (_) async => bytes,
          );
        } else {
          await FileSaver.instance.saveFile(
            name: name,
            bytes: bytes,
            fileExtension: 'pdf',
            mimeType: MimeType.pdf,
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              type == 'print'
                  ? 'Print dialog opened.'
                  : '${type.toUpperCase()} report created.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _label(String key) => key
      .replaceAll('_', ' ')
      .split(' ')
      .map((x) => x.isEmpty ? x : '${x[0].toUpperCase()}${x.substring(1)}')
      .join(' ');
  String _cell(dynamic value) {
    if (value == null) return '';
    if (value is Map || value is List) return value.toString();
    return value.toString();
  }

  Widget _reportTable(List<String> columns) {
    final visibleCount = _rows.length > 1000 ? 1000 : _rows.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final calculatedWidth = columns.isEmpty
            ? constraints.maxWidth
            : columns.length * 160.0;
        final tableWidth = calculatedWidth < constraints.maxWidth
            ? constraints.maxWidth
            : calculatedWidth;
        final scheme = Theme.of(context).colorScheme;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            height: constraints.maxHeight,
            child: Column(
              children: [
                Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    border: painting.Border(
                      bottom: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      for (final column in columns)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              _label(column),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: visibleCount,
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      return Container(
                        constraints: const BoxConstraints(minHeight: 42),
                        decoration: BoxDecoration(
                          border: painting.Border(
                            bottom: BorderSide(color: scheme.outlineVariant),
                          ),
                        ),
                        child: Row(
                          children: [
                            for (final column in columns)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    _cell(row[column]),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final columns = _columns;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports Center v5'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _run,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    initialValue: _reportKey,
                    decoration: const InputDecoration(
                      labelText: 'Report',
                      border: OutlineInputBorder(),
                    ),
                    items: _catalog
                        .map(
                          (report) => DropdownMenuItem<String>(
                            value: report['key']?.toString(),
                            child: Text(
                              '${report['category'] ?? 'Reports'} • '
                              '${report['name']?.toString() ?? report['key']?.toString() ?? 'Report'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _reportKey = value;
                        _invalidateResult();
                      });
                    },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(true),
                  icon: const Icon(Icons.date_range),
                  label: Text('From ${_date(_from)}'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(false),
                  icon: const Icon(Icons.event),
                  label: Text('To ${_date(_to)}'),
                ),
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _query,
                    decoration: const InputDecoration(
                      labelText: 'Search',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _run(),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : _run,
                  icon: const Icon(Icons.visibility),
                  label: const Text('View'),
                ),
                OutlinedButton.icon(
                  onPressed: _exporting || _rows.isEmpty
                      ? null
                      : () => _export('pdf'),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: _exporting || _rows.isEmpty
                      ? null
                      : () => _export('xlsx'),
                  icon: const Icon(Icons.table_view),
                  label: const Text('Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: _exporting || _rows.isEmpty
                      ? null
                      : () => _export('print'),
                  icon: const Icon(Icons.print),
                  label: const Text('Print'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                  ? const Center(
                      child: Text('No records for the selected filters.'),
                    )
                  : _reportTable(columns),
            ),
          ],
        ),
      ),
    );
  }
}
