import 'package:flutter/material.dart';

import '../../models/mobile_session.dart';
import '../../services/mobile_client_service.dart';
import '../../widgets/mobile_workspace_widgets.dart';
import 'mobile_expense_report_page.dart';

class MobileReportsCenterPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileReportsCenterPage({
    super.key,
    required this.session,
    required this.service,
    this.locationId,
  });

  @override
  State<MobileReportsCenterPage> createState() =>
      _MobileReportsCenterPageState();
}

class _MobileReportsCenterPageState extends State<MobileReportsCenterPage> {
  final _searchCtrl = TextEditingController();
  late Future<List<Map<String, dynamic>>> _catalogFuture;
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _load() {
    _catalogFuture = widget.service.reportsCatalog(widget.session);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _catalogFuture;
  }

  void _openReport(Map<String, dynamic> reportDef) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ReportRunnerPage(
          session: widget.session,
          service: widget.service,
          reportDef: reportDef,
          initialLocationId: widget.locationId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Intelligence'),
        actions: [
          IconButton(
            tooltip: 'Expense Analysis',
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MobileExpenseReportPage(
                  session: widget.session,
                  service: widget.service,
                  locationId: widget.locationId,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh catalog',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search business reports...',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _CategoryChip(
                  label: 'All',
                  selected: _selectedCategory == 'All',
                  onSelected: () => setState(() => _selectedCategory = 'All'),
                ),
                const SizedBox(width: 6),
                _CategoryChip(
                  label: 'Sales',
                  selected: _selectedCategory == 'Sales',
                  onSelected: () => setState(() => _selectedCategory = 'Sales'),
                ),
                const SizedBox(width: 6),
                _CategoryChip(
                  label: 'Inventory',
                  selected: _selectedCategory == 'Inventory',
                  onSelected: () => setState(() => _selectedCategory = 'Inventory'),
                ),
                const SizedBox(width: 6),
                _CategoryChip(
                  label: 'Purchase',
                  selected: _selectedCategory == 'Purchase',
                  onSelected: () => setState(() => _selectedCategory = 'Purchase'),
                ),
                const SizedBox(width: 6),
                _CategoryChip(
                  label: 'Accounting',
                  selected: _selectedCategory == 'Accounting',
                  onSelected: () => setState(() => _selectedCategory = 'Accounting'),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _catalogFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const WorkspaceLoadingList();
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 40, color: Theme.of(context).colorScheme.error),
                          const SizedBox(height: 10),
                          Text('Failed to load reports: ${snapshot.error}', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _refresh, child: const Text('Try Again')),
                        ],
                      ),
                    ),
                  );
                }

                final rawList = snapshot.data ?? [];
                final query = _searchCtrl.text.trim().toLowerCase();
                final filtered = rawList.where((r) {
                  final cat = (r['category'] ?? '').toString();
                  if (_selectedCategory != 'All' && cat.toLowerCase() != _selectedCategory.toLowerCase()) {
                    return false;
                  }
                  if (query.isEmpty) return true;
                  final title = (r['title'] ?? '').toString().toLowerCase();
                  final desc = (r['description'] ?? '').toString().toLowerCase();
                  return title.contains(query) || desc.contains(query);
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('No reports match your search'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = filtered[i];
                    final title = item['title'] ?? 'Report';
                    final desc = item['description'] ?? '';
                    final cat = item['category'] ?? 'General';

                    IconData catIcon;
                    switch (cat.toString().toLowerCase()) {
                      case 'sales':
                        catIcon = Icons.point_of_sale_rounded;
                        break;
                      case 'inventory':
                        catIcon = Icons.inventory_2_rounded;
                        break;
                      case 'purchase':
                        catIcon = Icons.shopping_bag_rounded;
                        break;
                      case 'accounting':
                        catIcon = Icons.account_balance_wallet_rounded;
                        break;
                      default:
                        catIcon = Icons.analytics_rounded;
                    }

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(catIcon, size: 20, color: Theme.of(context).colorScheme.onPrimaryContainer),
                        ),
                        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: desc.isNotEmpty
                            ? Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))
                            : null,
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                        onTap: () => _openReport(item),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ReportRunnerPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final Map<String, dynamic> reportDef;
  final String? initialLocationId;

  const _ReportRunnerPage({
    required this.session,
    required this.service,
    required this.reportDef,
    this.initialLocationId,
  });

  @override
  State<_ReportRunnerPage> createState() => _ReportRunnerPageState();
}

class _ReportRunnerPageState extends State<_ReportRunnerPage> {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();
  String? _locationId;
  Future<Map<String, dynamic>>? _runFuture;

  @override
  void initState() {
    super.initState();
    _locationId = widget.initialLocationId ?? widget.session.locationId;
    _run();
  }

  void _run() {
    final key = widget.reportDef['key']?.toString() ?? '';
    setState(() {
      _runFuture = widget.service.runReport(
        widget.session,
        reportKey: key,
        fromDate: _fromDate,
        toDate: _toDate,
        locationId: _locationId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.reportDef['title'] ?? 'Report';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Run again',
            icon: const Icon(Icons.play_arrow_rounded),
            onPressed: _run,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                        initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
                      );
                      if (picked != null && mounted) {
                        setState(() {
                          _fromDate = picked.start;
                          _toDate = picked.end;
                        });
                        _run();
                      }
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.date_range_rounded, size: 18),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${_fromDate.year}-${_fromDate.month.toString().padLeft(2, '0')}-${_fromDate.day.toString().padLeft(2, '0')} → '
                            '${_toDate.year}-${_toDate.month.toString().padLeft(2, '0')}-${_toDate.day.toString().padLeft(2, '0')}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _run,
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Update'),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _runFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Error generating report: ${snapshot.error}', textAlign: TextAlign.center),
                    ),
                  );
                }

                final result = snapshot.data ?? {};
                final rows = (result['rows'] as List? ?? const []).whereType<Map>().toList();
                final summary = (result['summary'] as List? ?? const []).whereType<Map>().toList();
                final definition = result['definition'] as Map? ?? widget.reportDef;
                final columns = (definition['columns'] as List? ?? const []).whereType<Map>().toList();

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (summary.isNotEmpty) ...[
                      const Text('Report Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 8),
                      ...summary.map((s) => Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 6),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(s['metric']?.toString() ?? s['label']?.toString() ?? ''),
                                  Text(
                                    s['amount']?.toString() ?? s['value']?.toString() ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          )),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Rows (${rows.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (rows.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        child: const Center(child: Text('No records found for the selected period')),
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 20,
                          horizontalMargin: 12,
                          columns: columns.isEmpty
                              ? (rows.first.keys.map((k) => DataColumn(label: Text(k))).toList())
                              : columns.map((col) {
                                  return DataColumn(
                                    label: Text(
                                      col['label']?.toString() ?? col['key']?.toString() ?? '',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  );
                                }).toList(),
                          rows: rows.map((r) {
                            final cells = columns.isEmpty
                                ? r.values.map((v) => DataCell(Text(v?.toString() ?? '—'))).toList()
                                : columns.map((col) {
                                    final val = r[col['key']];
                                    return DataCell(Text(val?.toString() ?? '—'));
                                  }).toList();
                            return DataRow(cells: cells);
                          }).toList(),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
