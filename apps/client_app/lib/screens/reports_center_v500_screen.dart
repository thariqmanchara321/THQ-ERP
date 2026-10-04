import 'dart:async';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../models/client_session.dart';
import '../models/report_document.dart';
import '../services/location_scope_service.dart';
import '../services/report_file_builder.dart';
import '../services/reports_center_service.dart';
import '../widgets/record_preview.dart';

class ReportsCenterV500Screen extends StatefulWidget {
  final ClientSession session;
  final ReportsCenterService? service;
  const ReportsCenterV500Screen({
    super.key,
    required this.session,
    this.service,
  });
  @override
  State<ReportsCenterV500Screen> createState() =>
      _ReportsCenterV500ScreenState();
}

class _ReportsCenterV500ScreenState extends State<ReportsCenterV500Screen> {
  final _query = TextEditingController();
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  late final ReportsCenterService _service =
      widget.service ?? ReportsCenterService();
  List<ReportDefinition> _catalog = [];
  ReportDefinition? _definition;
  ReportDocument? _report;
  ReportRequest? _loadedRequest;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  Timer? _searchTimer;
  int _generation = 0;
  int _offset = 0;
  int _pageSize = 100;
  String? _sortKey;
  bool _sortDescending = false;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  String? _category;

  @override
  void initState() {
    super.initState();
    LocationScopeService.selectedLocationId.addListener(_scopeChanged);
    _initialize();
  }

  @override
  void dispose() {
    _generation++;
    _searchTimer?.cancel();
    LocationScopeService.selectedLocationId.removeListener(_scopeChanged);
    _query.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.catalog(widget.session.business.id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _catalog = items;
        _definition = items.isEmpty ? null : items.first;
      });
      if (items.isEmpty) {
        setState(() {
          _loading = false;
          _error =
              'No reports are available for your enabled modules and permissions.';
        });
      } else {
        await _run();
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  void _scopeChanged() {
    _invalidate();
    _run();
  }

  void _invalidate() {
    _searchTimer?.cancel();
    _generation++;
    setState(() {
      _report = null;
      _loadedRequest = null;
      _offset = 0;
      _error = null;
      _loading = false;
    });
  }

  ReportRequest _request() => ReportRequest(
    tenantId: widget.session.business.id,
    key: _definition!.key,
    from: _from,
    to: _to,
    locationId: LocationScopeService.currentForRead(widget.session),
    query: _query.text.trim(),
    offset: _offset,
    limit: _pageSize,
    sortKey: _sortKey,
    sortDescending: _sortDescending,
  );
  Future<void> _run() async {
    if (_definition == null) return;
    _searchTimer?.cancel();
    final generation = ++_generation;
    final request = _request();
    setState(() {
      _loading = true;
      _report = null;
      _loadedRequest = null;
      _error = null;
    });
    try {
      final report = await _service.run(request);
      if (!mounted || generation != _generation) return;
      setState(() {
        _report = report;
        _loadedRequest = request;
        _loading = false;
      });
      if (_vertical.hasClients) _vertical.jumpTo(0);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  void _searchChanged(String value) {
    _invalidate();
    _searchTimer = Timer(const Duration(milliseconds: 400), _run);
  }

  Future<void> _date(bool start) async {
    final date = await showDatePicker(
      context: context,
      initialDate: start ? _from : _to,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (!mounted || date == null) return;
    setState(() {
      if (start) {
        _from = date;
        if (_to.isBefore(date)) _to = date;
      } else {
        _to = date;
        if (_from.isAfter(date)) _from = date;
      }
    });
    _invalidate();
    await _run();
  }

  void _chooseReport(ReportDefinition definition) {
    setState(() {
      _definition = definition;
      _sortKey = null;
      _sortDescending = false;
    });
    _invalidate();
    _run();
  }

  Future<void> _export(String format) async {
    final request = _loadedRequest;
    if (request == null || _loading || _exporting) return;
    setState(() {
      _exporting = true;
    });
    try {
      // Capture the loaded query. UI edits cannot relabel an export in progress.
      final report = await _service.run(request.exportRequest());
      report.requireComplete();
      final name =
          'THQ_${report.definition.key}_${report.context['from']}_${report.context['to']}';
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
        final fonts = await Future.wait([
          rootBundle.load('assets/report_fonts/ReportSans.ttf'),
          rootBundle.load('assets/report_fonts/ReportSans-Bold.ttf'),
          rootBundle.load('assets/report_fonts/NotoSansMalayalam.ttf'),
          rootBundle.load('assets/report_fonts/NotoSansDevanagari.ttf'),
        ]);
        bytes = await ReportFileBuilder.pdf(
          report,
          regular: fonts[0],
          bold: fonts[1],
          fallback: fonts.skip(2).toList(),
          evidence: format == 'pdf_details',
        );
        extension = 'pdf';
        mime = MimeType.pdf;
      }
      if (!mounted) return;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${report.totalRows} matching records exported.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
        });
      }
    }
  }

  Widget _selector() {
    final items = _category == null
        ? _catalog
        : _catalog.where((r) => r.category == _category).toList();
    return DropdownButtonFormField<String>(
      key: ValueKey(_definition?.key),
      initialValue: _definition?.key,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Report',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: items
          .map(
            (d) => DropdownMenuItem(
              value: d.key,
              child: Text(d.title, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: _exporting
          ? null
          : (key) {
              if (key != null) {
                _chooseReport(_catalog.firstWhere((d) => d.key == key));
              }
            },
    );
  }

  Widget _scopeSelector({VoidCallback? refresh}) =>
      DropdownButtonFormField<String>(
        key: ValueKey(
          'scope-${LocationScopeService.currentForRead(widget.session)}',
        ),
        initialValue: LocationScopeService.currentForRead(widget.session) ?? '',
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Store',
          border: OutlineInputBorder(),
          isDense: true,
        ),
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
            : (value) {
                if (value == null) return;
                if (value.isEmpty) {
                  LocationScopeService.selectAll(widget.session);
                } else {
                  LocationScopeService.select(widget.session, value);
                }
                refresh?.call();
              },
      );
  Widget _dateButton(
    bool start, {
    VoidCallback? refresh,
  }) => OutlinedButton.icon(
    onPressed: _exporting
        ? null
        : () async {
            await _date(start);
            refresh?.call();
          },
    icon: const Icon(Icons.calendar_month, size: 17),
    label: Text(
      '${start ? 'From' : 'To'} ${DateFormat('dd MMM yyyy').format(start ? _from : _to)}',
    ),
  );
  Widget _exportMenu() => PopupMenuButton<String>(
    enabled: _report != null && !_loading && !_exporting,
    tooltip: 'Export every matching record',
    onSelected: _export,
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'xlsx', child: Text('Excel + complete evidence')),
      PopupMenuItem(value: 'pdf', child: Text('PDF report')),
      PopupMenuItem(
        value: 'pdf_details',
        child: Text('PDF + all saved evidence'),
      ),

      PopupMenuItem(value: 'json', child: Text('Complete JSON')),
      PopupMenuItem(value: 'print', child: Text('Print report')),
    ],
    child: const Padding(
      padding: EdgeInsets.all(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.download, size: 19),
          SizedBox(width: 6),
          Text('Export'),
        ],
      ),
    ),
  );
  Future<void> _filters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Report filters',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _scopeSelector(
                refresh: () {
                  if (sheetContext.mounted) update(() {});
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _dateButton(
                    true,
                    refresh: () {
                      if (sheetContext.mounted) update(() {});
                    },
                  ),
                  _dateButton(
                    false,
                    refresh: () {
                      if (sheetContext.mounted) update(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _query,
                decoration: const InputDecoration(
                  labelText: 'Search all saved fields',
                  border: OutlineInputBorder(),
                ),
                onChanged: _searchChanged,
                onSubmitted: (_) => _run(),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _run();
                },
                child: const Text('Run report'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar(bool compact) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: MediaQuery.textScalerOf(context).scale(22) + 20,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final category in [
                'All',
                ..._catalog.map((r) => r.category).toSet(),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: (_category ?? 'All') == category,
                    onSelected: _exporting
                        ? null
                        : (_) {
                            setState(() {
                              _category = category == 'All' ? null : category;
                            });
                            if (_category != null &&
                                _definition?.category != _category) {
                              _chooseReport(
                                _catalog.firstWhere(
                                  (r) => r.category == _category,
                                ),
                              );
                            }
                          },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (compact)
          Row(
            children: [
              Expanded(child: _selector()),
              IconButton(
                tooltip: 'Dates, store and search',
                onPressed: _exporting ? null : _filters,
                icon: const Icon(Icons.tune),
              ),
              IconButton(
                tooltip: 'Run report',
                onPressed: _exporting ? null : _run,
                icon: const Icon(Icons.refresh),
              ),
            ],
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: 330, child: _selector()),
              SizedBox(width: 230, child: _scopeSelector()),
              _dateButton(true),
              _dateButton(false),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _query,
                  enabled: !_exporting,
                  decoration: const InputDecoration(
                    labelText: 'Search all saved fields',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: _searchChanged,
                  onSubmitted: (_) => _run(),
                ),
              ),
              FilledButton.icon(
                onPressed: _exporting ? null : _run,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Run'),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Text(
          '${_definition?.dateBasis ?? ''}\n${_definition?.description ?? ''}',
          maxLines: compact ? 3 : 4,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (compact)
          Text(
            '${DateFormat('dd MMM yyyy').format(_from)} – ${DateFormat('dd MMM yyyy').format(_to)} • ${LocationScopeService.scopeLabel(widget.session)}',
            maxLines: 2,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ),
  );
  Widget _summary(ReportDocument report) {
    if (report.summary.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.context['summary_basis']?.toString() ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(60) + 28,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: report.summary.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final metric = report.summary[index];
                return Container(
                  width: 220,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metric['label']?.toString() ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const Spacer(),
                      Text(
                        report.format(
                          metric['value'],
                          metric['type']?.toString() ?? 'text',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
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
    );
  }

  Widget _cell(
    String text,
    double width, {
    bool numeric = false,
    bool heading = false,
    VoidCallback? tap,
    IconData? icon,
  }) => SizedBox(
    width: width,
    child: InkWell(
      onTap: tap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisAlignment: numeric
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Expanded(
              child: Tooltip(
                message: text,
                child: Text(
                  text,
                  textAlign: numeric ? TextAlign.right : TextAlign.left,
                  maxLines: heading ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: heading ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
            if (icon != null) Icon(icon, size: 14),
          ],
        ),
      ),
    ),
  );
  Widget _table(ReportDocument report) {
    if (report.rows.isEmpty) {
      return const Center(
        child: Text('No matching records. Change dates, store or search.'),
      );
    }
    final width = report.columns.fold<double>(62, (sum, c) => sum + c.width);
    return Scrollbar(
      controller: _horizontal,
      thumbVisibility: true,
      notificationPredicate: (n) => n.depth == 0,
      child: SingleChildScrollView(
        controller: _horizontal,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 62,
                      height: 48,
                      child: Center(child: Text('#')),
                    ),
                    for (final column in report.columns)
                      _cell(
                        column.label,
                        column.width,
                        heading: true,
                        numeric: column.numeric,
                        icon: _sortKey == column.key
                            ? (_sortDescending
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward)
                            : null,
                        tap: _exporting
                            ? null
                            : () {
                                setState(() {
                                  _sortDescending = _sortKey == column.key
                                      ? !_sortDescending
                                      : false;
                                  _sortKey = column.key;
                                });
                                _invalidate();
                                _run();
                              },
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Scrollbar(
                  controller: _vertical,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _vertical,
                    itemExtent: 46,
                    itemCount: report.rows.length,
                    itemBuilder: (context, index) {
                      final row = report.rows[index];
                      return Material(
                        color: index.isEven
                            ? Theme.of(context).colorScheme.surface
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                        child: InkWell(
                          onTap: () => RecordPreview.show(
                            context,
                            title:
                                '${report.definition.title} • Record ${report.offset + index + 1}',
                            record: row,
                            currency: widget.session.currencyCode,
                          ),
                          child: Row(
                            children: [
                              _cell('${report.offset + index + 1}', 62),
                              for (final column in report.columns)
                                _cell(
                                  report.cell(row, column),
                                  column.width,
                                  numeric: column.numeric,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pagination(ReportDocument report, bool compact) => Padding(
    padding: const EdgeInsets.all(8),
    child: Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: [
        Text(
          report.totalRows == 0
              ? '0 matching records'
              : '${report.offset + 1}–${report.offset + report.rows.length} of ${report.totalRows} records',
        ),
        if (!compact) const Text('Open a row for complete saved details'),
        DropdownButton<int>(
          value: _pageSize,
          items: [50, 100, 200]
              .map(
                (size) =>
                    DropdownMenuItem(value: size, child: Text('$size / page')),
              )
              .toList(),
          onChanged: _exporting
              ? null
              : (size) {
                  if (size == null) return;
                  setState(() {
                    _pageSize = size;
                  });
                  _invalidate();
                  _run();
                },
        ),
        IconButton(
          tooltip: 'Previous page',
          onPressed: report.offset > 0 && !_exporting
              ? () {
                  setState(() {
                    _offset = (_offset - _pageSize).clamp(0, report.totalRows);
                  });
                  _run();
                }
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: 'Next page',
          onPressed:
              report.offset + report.rows.length < report.totalRows &&
                  !_exporting
              ? () {
                  setState(() {
                    _offset += _pageSize;
                  });
                  _run();
                }
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Reports Center v5'),
      actions: [
        if (_exporting)
          const Padding(
            padding: EdgeInsets.all(15),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        _exportMenu(),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 700 || constraints.maxHeight < 500;
        final report = _report;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(compact),
            if (_loading) const LinearProgressIndicator(),
            if (report != null && constraints.maxHeight >= 520)
              _summary(report),
            Expanded(
              child: _error != null
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _definition == null
                                  ? _initialize
                                  : _run,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : report != null
                  ? _table(report)
                  : Center(
                      child: Text(
                        _loading
                            ? 'Loading report…'
                            : 'Choose a report and run it.',
                      ),
                    ),
            ),
            if (report != null) _pagination(report, compact),
          ],
        );
      },
    ),
  );
}
