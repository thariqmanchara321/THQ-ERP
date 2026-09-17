import 'package:flutter/material.dart';

import 'logistics_api.dart';
import 'logistics_operations_workspace.dart';

class VehicleLogisticsReportWorkspace extends StatefulWidget {
  final String tenantId;
  final String? locationId;
  final WidgetBuilder? legacyTransferBuilder;

  const VehicleLogisticsReportWorkspace({
    super.key,
    required this.tenantId,
    this.locationId,
    this.legacyTransferBuilder,
  });

  @override
  State<VehicleLogisticsReportWorkspace> createState() =>
      _VehicleLogisticsReportWorkspaceState();
}

class _VehicleLogisticsReportWorkspaceState
    extends State<VehicleLogisticsReportWorkspace> {
  final api = ThqLogisticsApi();
  final search = TextEditingController();
  DateTime from = DateTime.now();
  DateTime to = DateTime.now();
  bool loading = true;
  String? error;
  Map<String, dynamic> dashboard = {};
  List<Map<String, dynamic>> rows = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  String clean(Object value) => value
      .toString()
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('Exception: ', '');

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await Future.wait([
        api.dashboard(tenantId: widget.tenantId, from: from, to: to),
        api.operations(
          tenantId: widget.tenantId,
          locationId: widget.locationId,
          query: search.text.trim().isEmpty ? null : search.text.trim(),
        ),
      ]);
      if (!mounted) return;
      final fromDay = DateTime(from.year, from.month, from.day);
      final toDay = DateTime(to.year, to.month, to.day);
      setState(() {
        dashboard = result[0] as Map<String, dynamic>;
        rows = (result[1] as List<Map<String, dynamic>>).where((row) {
          final d = DateTime.tryParse(row['operation_date']?.toString() ?? '');
          if (d == null) return true;
          final day = DateTime(d.year, d.month, d.day);
          return !day.isBefore(fromDay) && !day.isAfter(toDay);
        }).toList();
      });
    } catch (e) {
      if (mounted) setState(() => error = clean(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> pickRange() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDateRange: DateTimeRange(start: from, end: to),
    );
    if (result != null) {
      setState(() {
        from = result.start;
        to = result.end;
      });
      await load();
    }
  }

  Future<void> open(Map<String, dynamic> row) async {
    await showDialog<void>(
      context: context,
      builder: (_) => LogisticsOperationDialog(
        api: api,
        tenantId: widget.tenantId,
        locationId: widget.locationId,
        operationId: row['id'].toString(),
        readOnly: true,
      ),
    );
  }

  Widget metric(String label, dynamic value, IconData icon) => SizedBox(
    width: 150,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 7),
            Text(
              '${value ?? 0}',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(label),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Vehicle Logistics'),
      actions: [
        if (widget.legacyTransferBuilder != null)
          TextButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: widget.legacyTransferBuilder!)),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Transfer Logistics'),
          ),
        IconButton(
          tooltip: 'Date range',
          onPressed: pickRange,
          icon: const Icon(Icons.date_range),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: load,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  'Control Center',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text('${shortDate(from)} - ${shortDate(to)}'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    metric(
                      'Operations',
                      dashboard['operations_total'],
                      Icons.route,
                    ),
                    metric(
                      'Active',
                      dashboard['operations_active'],
                      Icons.play_circle_outline,
                    ),
                    metric(
                      'Trucks on road',
                      dashboard['runs_on_road'],
                      Icons.local_shipping,
                    ),
                    metric(
                      'Collected',
                      qty(dashboard['pickup_primary_qty']),
                      Icons.call_received,
                    ),
                    metric(
                      'Delivered',
                      qty(dashboard['delivery_primary_qty']),
                      Icons.call_made,
                    ),
                    metric(
                      'Returned',
                      qty(dashboard['returned_primary_qty']),
                      Icons.keyboard_return,
                    ),
                    metric(
                      'Variance',
                      qty(dashboard['variance_primary_qty']),
                      Icons.warning_amber,
                    ),
                    metric(
                      'Variance stops',
                      dashboard['variance_stops'],
                      Icons.report_problem_outlined,
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: search,
                  onSubmitted: (_) => load(),
                  decoration: InputDecoration(
                    hintText: 'Search operation, truck, driver or reference',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      onPressed: load,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                if (rows.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: Text('No logistics history found.')),
                    ),
                  )
                else
                  ...rows.map(
                    (row) => Card(
                      child: ListTile(
                        onTap: () => open(row),
                        leading: const CircleAvatar(
                          child: Icon(Icons.local_shipping_outlined),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                row['operation_number']?.toString() ?? '-',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            statusChip(row['status']?.toString() ?? 'planned'),
                          ],
                        ),
                        subtitle: Text(
                          '${row['run_count'] ?? 0} run(s) | ${row['stop_count'] ?? 0} stop(s) | '
                          'Pickup ${qty(row['pickup_primary_qty'])} | Delivery ${qty(row['delivery_primary_qty'])} | '
                          'Return ${qty(row['returned_primary_qty'])} | Variance ${qty(row['variance_primary_qty'])}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    ),
                  ),
              ],
            ),
          ),
  );
}
