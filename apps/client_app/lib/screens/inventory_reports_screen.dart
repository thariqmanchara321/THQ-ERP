import 'package:thq_ui/thq_ui.dart';
import 'dart:async';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../models/client_session.dart';
import '../models/inventory_report.dart';
import '../models/record_presentation.dart';
import '../models/report_document.dart';
import '../services/inventory_report_service.dart';
import '../services/location_scope_service.dart';
import '../services/report_file_builder.dart';
import '../widgets/inventory_report_table.dart';
import '../widgets/record_preview.dart';

class InventoryReportsScreen extends StatefulWidget {
  final ClientSession session;
  final InventoryReportService? service;
  const InventoryReportsScreen({
    super.key,
    required this.session,
    this.service,
  });
  @override
  State<InventoryReportsScreen> createState() => _InventoryReportsScreenState();
}

class _InventoryReportsScreenState extends State<InventoryReportsScreen> {
  late final _service = widget.service ?? InventoryReportService();
  final _search = TextEditingController();
  final _vertical = ScrollController();
  List<ReportDefinition> _catalog = [];
  ReportDefinition? _definition;
  InventoryReportResult? _result;
  InventoryReportRequest? _loaded;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1),
      _to = DateTime.now();
  int _days = 30,
      _expiryDays = 30,
      _offset = 0,
      _pageSize = 50,
      _generation = 0;
  bool _loading = true,
      _exporting = false,
      _descending = false,
      _showSummary = true;
  String? _error, _sort;
  Map<String, String> _filters = {};
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    LocationScopeService.selectedLocationId.addListener(_scopeChanged);
    _initialize();
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    LocationScopeService.selectedLocationId.removeListener(_scopeChanged);
    _search.dispose();
    _vertical.dispose();
    super.dispose();
  }

  void _scopeChanged() {
    _offset = 0;
    _run();
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    if (!canOpenInventoryReports(widget.session)) {
      setState(() {
        _loading = false;
        _error = 'Inventory and Reports view access is required.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.catalog(widget.session.business.id);
      if (!mounted || generation != _generation) {
        return;
      }
      if (rows.isEmpty) {
        throw StateError('No inventory reports are available for your access.');
      }
      setState(() {
        _catalog = rows;
        _definition = rows.first;
      });
      await _run();
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  InventoryReportRequest _request() => InventoryReportRequest(
    tenantId: widget.session.business.id,
    key: _definition!.key,
    from: _from,
    to: _to,
    locationId: LocationScopeService.currentForRead(widget.session),
    query: _search.text.trim(),
    offset: _offset,
    limit: _pageSize,
    days: _days,
    expiryDays: _expiryDays,
    filters: _filters,
    sortKey: _sort,
    sortDescending: _descending,
  );
  Future<void> _run() async {
    if (_definition == null) {
      return;
    }
    _debounce?.cancel();
    final generation = ++_generation;
    final request = _request();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _loaded = null;
    });
    try {
      final result = await _service.run(request);
      if (!mounted || generation != _generation) {
        return;
      }
      if (result.document.definition.key != request.key ||
          result.document.offset != request.offset) {
        throw StateError('The report changed. Refresh it.');
      }
      setState(() {
        _result = result;
        _loaded = request;
        _loading = false;
      });
      if (_vertical.hasClients) {
        _vertical.jumpTo(0);
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  void _choose(ReportDefinition d) {
    _definition = d;
    _offset = 0;
    _filters = {};
    _sort = null;
    _descending = false;
    _run();
  }

  void _searchChanged(String v) {
    _debounce?.cancel();
    _generation++;
    setState(() {
      _offset = 0;
      _result = null;
      _loaded = null;
      _loading = true;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 350), _run);
  }

  void _notice(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> _export(String format) async {
    final request = _loaded;
    if (request == null || _loading || _exporting) {
      return;
    }
    final generation = _generation;
    setState(() {
      _exporting = true;
    });
    try {
      final result = await _service.run(request.forExport());
      final report = result.presentation;
      report.requireComplete();
      if (!mounted || generation != _generation) {
        throw StateError(
          'Report filters changed. Export the refreshed report.',
        );
      }
      Uint8List bytes;
      var extension = format;
      var mime = MimeType.other;
      if (format == 'xlsx') {
        bytes = ReportFileBuilder.excel(report);
        mime = MimeType.microsoftExcel;
      } else if (format == 'json') {
        bytes = ReportFileBuilder.json(report);
        mime = MimeType.json;
      } else {
        final fonts = await Future.wait(
          [
            'ReportSans.ttf',
            'ReportSans-Bold.ttf',
            'NotoSansMalayalam.ttf',
            'NotoSansDevanagari.ttf',
          ].map((f) => rootBundle.load('assets/report_fonts/$f')),
        );
        bytes = await ReportFileBuilder.pdf(
          report,
          regular: fonts[0],
          bold: fonts[1],
          fallback: fonts.skip(2).toList(),
        );
        extension = 'pdf';
        mime = MimeType.pdf;
      }
      if (!mounted || generation != _generation) {
        return;
      }
      final name =
          'THQ_Inventory_${request.key}_${DateFormat('yyyyMMdd').format(request.to)}';
      if (format == 'print') {
        await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
      } else {
        await FileSaver.instance.saveFile(
          name: name,
          bytes: bytes,
          fileExtension: extension,
          mimeType: mime,
        );
      }
      if (mounted) {
        _notice('${report.totalRows} matching records exported.');
      }
    } catch (e) {
      if (mounted) {
        _notice('Export failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
        });
      }
    }
  }

  Future<void> _filterDialog() async {
    var from = _from, to = _to, days = _days, expiry = _expiryDays;
    final filters = Map<String, String>.from(_filters);
    final unit = TextEditingController(text: filters['unit_code'] ?? ''),
        status = TextEditingController(text: filters['status'] ?? '');
    final applied = await showThqDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          Future<void> pick(bool start) async {
            final date = await showDatePicker(
              context: ctx,
              initialDate: start ? from : to,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (date != null && ctx.mounted) {
              update(() {
                if (start) {
                  from = date;
                } else {
                  to = date;
                }
              });
            }
          }

          return AlertDialog(
            title: const Text('Inventory report filters'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_definition?.description ?? ''),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => pick(true),
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(
                            'From ${DateFormat('dd MMM yyyy').format(from)}',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => pick(false),
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(
                            'To ${DateFormat('dd MMM yyyy').format(to)}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: days,
                      decoration: const InputDecoration(
                        labelText: 'Sales / activity lookback',
                      ),
                      items: [7, 30, 60, 90, 180, 365]
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text('$v days'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => update(() {
                        days = v ?? days;
                      }),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: expiry,
                      decoration: const InputDecoration(
                        labelText: 'Expiry watch from today',
                      ),
                      items: [0, 7, 30, 60, 90, 180, 365]
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(
                                v == 0
                                    ? 'Expired / expires today'
                                    : 'Next $v days',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => update(() {
                        expiry = v ?? expiry;
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: unit,
                      decoration: const InputDecoration(
                        labelText: 'Base unit',
                        hintText: 'CFT, NOS… (blank = all)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        hintText: 'low_stock, in_stock… (blank = all)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: filters['tracking_mode'] ?? '',
                      decoration: const InputDecoration(
                        labelText: 'Tracking mode',
                      ),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('All modes')),
                        DropdownMenuItem(
                          value: 'quantity',
                          child: Text('Quantity'),
                        ),
                        DropdownMenuItem(value: 'batch', child: Text('Batch')),
                        DropdownMenuItem(
                          value: 'serial',
                          child: Text('Serial'),
                        ),
                      ],
                      onChanged: (v) => update(() {
                        filters['tracking_mode'] = v ?? '';
                      }),
                    ),
                    if (from.isAfter(to))
                      const Text('From date must precede the To date.'),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: from.isAfter(to)
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text('Apply filters'),
              ),
            ],
          );
        },
      ),
    );
    final unitText = unit.text.trim().toUpperCase(),
        statusText = status.text.trim().toLowerCase().replaceAll(' ', '_');
    unit.dispose();
    status.dispose();
    if (applied != true || !mounted) {
      return;
    }
    filters['unit_code'] = unitText;
    filters['status'] = statusText;
    _from = from;
    _to = to;
    _days = days;
    _expiryDays = expiry;
    _filters = {
      for (final e in filters.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };
    _offset = 0;
    _run();
  }

  InputDecoration _input(String label, {IconData? icon}) => InputDecoration(
    labelText: label,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(7)),
    labelStyle: const TextStyle(fontSize: 12),
    prefixIcon: icon == null ? null : Icon(icon, size: 18),
    prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
  );

  Widget _toolbar() => LayoutBuilder(
    builder: (context, space) {
      final wide = space.maxWidth >= 900;
      final small = space.maxWidth < 500;
      final reportPicker = DropdownButtonFormField<String>(
        key: ValueKey(_definition?.key),
        initialValue: _definition?.key,
        isExpanded: true,
        isDense: true,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        decoration: _input('Inventory report'),
        items: _catalog
            .map(
              (d) => DropdownMenuItem(
                value: d.key,
                child: Text(d.title, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: _exporting
            ? null
            : (v) {
                if (v != null) _choose(_catalog.firstWhere((d) => d.key == v));
              },
      );
      final scope = DropdownButtonFormField<String>(
        key: ValueKey(
          'inventory-scope-${LocationScopeService.currentForRead(widget.session)}',
        ),
        initialValue: LocationScopeService.currentForRead(widget.session) ?? '',
        isExpanded: true,
        isDense: true,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        decoration: _input('Report store'),
        items: [
          if (widget.session.canViewAllLocations ||
              LocationScopeService.currentForRead(widget.session) == null)
            const DropdownMenuItem(
              value: '',
              child: Text(
                'All authorized stores',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ...LocationScopeService.orderedLocations(widget.session).map(
            (l) => DropdownMenuItem(
              value: l.id,
              child: Text(l.name, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: _exporting
            ? null
            : (v) {
                if (v == null) return;
                if (v.isEmpty) {
                  LocationScopeService.selectAll(widget.session);
                } else {
                  LocationScopeService.select(widget.session, v);
                }
              },
      );
      final search = TextField(
        controller: _search,
        enabled: !_exporting,
        onChanged: _searchChanged,
        style: const TextStyle(fontSize: 12),
        decoration: _input(
          'Search product, SKU or reference',
          icon: Icons.search,
        ),
      );
      final actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: _filters.isEmpty
                ? 'Filters and dates'
                : 'Filters and dates (${_filters.length} active)',
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: const EdgeInsets.all(7),
            iconSize: 18,
            onPressed: _exporting || _definition == null ? null : _filterDialog,
            icon: Badge(
              isLabelVisible: _filters.isNotEmpty,
              label: Text('${_filters.length}'),
              child: const Icon(Icons.tune),
            ),
          ),
          IconButton(
            tooltip: 'Refresh report',
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: const EdgeInsets.all(7),
            iconSize: 18,
            onPressed: _exporting
                ? null
                : () {
                    if (_definition == null) {
                      _initialize();
                    } else {
                      _run();
                    }
                  },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: _showSummary
                ? 'Hide totals · more table space'
                : 'Show totals',
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: const EdgeInsets.all(7),
            iconSize: 18,
            onPressed: () => setState(() => _showSummary = !_showSummary),
            icon: Icon(_showSummary ? Icons.expand_less : Icons.expand_more),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('inventory-export'),
            tooltip: 'Export all matching records',
            enabled: !_exporting && !_loading && _loaded != null,
            onSelected: _export,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'xlsx',
                child: Text('Excel · all matching records'),
              ),
              PopupMenuItem(
                value: 'pdf',
                child: Text('PDF · all matching records'),
              ),
              PopupMenuItem(value: 'print', child: Text('Print report')),
              PopupMenuItem(
                value: 'json',
                child: Text('JSON · readable report data'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_exporting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.file_download_outlined, size: 17),
                  const SizedBox(width: 5),
                  Text(
                    _exporting ? 'Exporting…' : 'Export',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      if (wide) {
        return Row(
          children: [
            SizedBox(width: 230, child: reportPicker),
            const SizedBox(width: 6),
            SizedBox(width: 180, child: scope),
            const SizedBox(width: 6),
            Expanded(child: search),
            const SizedBox(width: 4),
            actions,
          ],
        );
      }
      final storeWidth = small ? (space.maxWidth - 6) * .44 : 180.0;
      return Wrap(
        spacing: 6,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: small ? space.maxWidth : 250, child: reportPicker),
          SizedBox(width: storeWidth, child: scope),
          SizedBox(
            width: small
                ? space.maxWidth - storeWidth - 6
                : (space.maxWidth - 200).clamp(220, 400),
            child: search,
          ),
          actions,
        ],
      );
    },
  );

  Widget _metric(String label, String value, {bool alert = false}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: alert
            ? colors.errorContainer.withValues(alpha: .45)
            : colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .7)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(
                color: alert ? colors.error : colors.onSurfaceVariant,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  Widget _summary(ReportDocument report) {
    const relevant = <String, Set<String>>{
      'stock_snapshot': {'low_stock', 'review', 'stock_value'},
      'valuation': {'stock_value'},
      'stock_statement': {'review'},
      'reorder': {'low_stock'},
      'activity': {'non_moving'},
      'reconciliation': {'review'},
    };
    const labels = {
      'low_stock': 'Low stock',
      'review': 'Gaps',
      'stock_value': 'Stock value',
      'non_moving': 'Non-moving',
    };
    return Wrap(
      spacing: 6,
      runSpacing: 5,
      children: [
        for (final s in report.summary)
          if ((relevant[report.definition.key] ?? {}).contains(s['key']))
            _metric(
              labels[s['key']] ?? '${s['label']}',
              report.format(s['value'], '${s['type']}'),
              alert: s['key'] == 'review' && (s['value'] as num? ?? 0) > 0,
            ),
        for (final u in _result!.units)
          if (u['quantity'] != null || u['closing_quantity'] != null)
            _metric(
              '${u['unit_code']}',
              '${report.format(u['closing_quantity'] ?? u['quantity'], 'number')} ${switch (report.definition.key) {
                'stock_statement' => 'closing',
                'transfers' => 'requested',
                'tracking_events' => 'event qty',
                'warranties' => 'covered',
                _ => 'on hand',
              }}${u['available'] == null ? '' : ' · ${report.format(u['available'], 'number')} available'}',
            ),
      ],
    );
  }

  Widget _table(ReportDocument report) => InventoryReportTable(
    report: report,
    controller: _vertical,
    sortKey: _sort,
    descending: _descending,
    disabled: _exporting,
    showStore: LocationScopeService.currentForRead(widget.session) == null,
    onSort: (key) {
      _descending = _sort == key ? !_descending : false;
      _sort = key;
      _offset = 0;
      _run();
    },
    onOpen: (row) => RecordPreview.show(
      context,
      title:
          '${report.definition.title} · ${row['sku'] ?? row['reference_number'] ?? 'Record'}',
      record: RecordPresentation.report(row),
      currency: widget.session.currencyCode,
    ),
  );

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 32),
              const SizedBox(height: 12),
              SelectableText(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _definition == null ? _initialize : _run,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final report = _result?.document;
    if (report == null || report.rows.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 36),
            SizedBox(height: 10),
            Text('No matching inventory records'),
          ],
        ),
      );
    }
    return _table(report);
  }

  Widget _footer() {
    final r = _result?.document, count = r?.totalRows ?? 0;
    final colors = Theme.of(context).colorScheme;
    final label = Text(
      count == 0
          ? '0 records'
          : '${_offset + 1}–${_offset + (r?.rows.length ?? 0)} of $count records',
      style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
    );
    final paging = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Rows ',
          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _pageSize,
            isDense: true,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: colors.onSurface,
            ),
            items: [25, 50, 100, 250]
                .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                .toList(),
            onChanged: _exporting
                ? null
                : (v) {
                    _pageSize = v ?? 50;
                    _offset = 0;
                    _run();
                  },
          ),
        ),
        IconButton(
          tooltip: 'Previous page',
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          padding: const EdgeInsets.all(5),
          iconSize: 18,
          onPressed: _loading || _exporting || _offset == 0
              ? null
              : () {
                  _offset = (_offset - _pageSize).clamp(0, count);
                  _run();
                },
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: 'Next page',
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          padding: const EdgeInsets.all(5),
          iconSize: 18,
          onPressed: _loading || _exporting || _offset + _pageSize >= count
              ? null
              : () {
                  _offset += _pageSize;
                  _run();
                },
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: LayoutBuilder(
        builder: (context, space) => space.maxWidth >= 500
            ? Row(
                children: [
                  Expanded(child: label),
                  paging,
                ],
              )
            : Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [label, paging],
              ),
      ),
    );
  }

  String get _period => _definition?.basis == 'current'
      ? 'Current balances · $_days-day activity · $_expiryDays-day expiry watch'
      : '${DateFormat('dd MMM yyyy').format(_from)} – ${DateFormat('dd MMM yyyy').format(_to)} · ${switch (_definition?.basis) {
          'as_of' => 'stock posting dates',
          'expiry' => 'coverage expiry dates',
          'period_current' => 'creation dates · current status',
          _ => 'posting dates',
        }}';

  Widget _controls() {
    final colors = Theme.of(context).colorScheme, report = _result?.document;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _toolbar(),
        const SizedBox(height: 4),
        Wrap(
          spacing: 3,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final category in _catalog.map((d) => d.category).toSet())
              TextButton(
                onPressed: _exporting
                    ? null
                    : () => _choose(
                        _catalog.firstWhere((d) => d.category == category),
                      ),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: _definition?.category == category
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                  backgroundColor: _definition?.category == category
                      ? colors.primaryContainer
                      : null,
                  textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                child: Text(category),
              ),
            if (_definition != null)
              Tooltip(
                message:
                    '${_definition!.description}\n$_period\n${report?.context['quantity_basis'] ?? 'Quantities use the configured base unit.'}\n${report?.context['stock_basis'] ?? ''}',
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.info_outline,
                    size: 15,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        if (_definition != null)
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 4),
            child: Text(
              _period,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ),
        if (report != null && _showSummary) _summary(report),
        if (report != null &&
            report.summary.any(
              (s) => s['key'] == 'review' && (s['value'] as num? ?? 0) > 0,
            ))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Stock / tracking gaps need review. Open Stock and tracking checks for details.',
              style: TextStyle(color: colors.error, fontSize: 11),
            ),
          ),
        if (_definition?.key == 'tracking_changes' &&
            report?.context['tracking_change_history_available'] == false)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Tracking change history is not installed for this backend.',
              style: TextStyle(fontSize: 11),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: Navigator.of(context).canPop()
        ? AppBar(title: const Text('Inventory Reports'))
        : null,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
        child: LayoutBuilder(
          builder: (ctx, space) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      space.maxHeight * (space.maxHeight < 560 ? .55 : .4),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 6),
                  child: _controls(),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(ctx).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: _body(),
                ),
              ),
              _footer(),
            ],
          ),
        ),
      ),
    ),
  );
}
