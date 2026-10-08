import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/aggregate_yard_service.dart';
import '../services/location_scope_service.dart';
import '../services/operational_export_service.dart';
import '../services/staff_load_service.dart';
import '../widgets/record_preview.dart';

class MaterialLoadReportsScreen extends StatefulWidget {
  final ClientSession session;
  const MaterialLoadReportsScreen({super.key, required this.session});
  @override
  State<MaterialLoadReportsScreen> createState() =>
      _MaterialLoadReportsScreenState();
}

class _MaterialLoadReportsScreenState extends State<MaterialLoadReportsScreen> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _to = DateTime.now();
  Map<String, dynamic> _context = const {};
  Map<String, dynamic> _data = const {};
  bool _busy = true;
  String? _error;
  String? _vehicle;
  String? _driver;
  final _export = OperationalExportService();
  List<Map<String, dynamic>> get _loads =>
      StaffLoadService.rows(_data['loads']);
  String _money(double v) =>
      '${widget.session.currencyCode} ${v.toStringAsFixed(2)}';
  @override
  void initState() {
    super.initState();
    LocationScopeService.selectedLocationId.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    LocationScopeService.selectedLocationId.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      final contextData = await AggregateYardService().context(
        tenantId: widget.session.business.id,
      );
      final data = await StaffLoadService().load(
        tenantId: widget.session.business.id,
        action: 'report',
        locationId: LocationScopeService.currentForRead(widget.session),
        data: {
          'from': StaffLoadService.date(_from),
          'to': StaffLoadService.date(_to),
          'vehicle_id': _vehicle,
          'driver_id': _driver,
        },
      );
      if (mounted) {
        setState(() {
          _context = contextData;
          _data = data;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _exportData() => {
    'period': {
      'from': StaffLoadService.date(_from),
      'to': StaffLoadService.date(_to),
      'location': LocationScopeService.scopeLabel(widget.session),
      'vehicle_id': _vehicle,
      'driver_id': _driver,
    },
    'loads': [
      for (final load in _loads)
        {
          for (final entry in load.entries)
            if (entry.value is! List) entry.key: entry.value,
        },
    ],
    for (final key in [
      'costs',
      'cost_payments',
      'staff_payments',
      'customer_payments',
      'legacy_freight_payments',
      'history',
      'load_events',
    ])
      key: [
        for (final load in _loads)
          for (final row in StaffLoadService.rows(load[key]))
            {
              ...row,
              'load_id': load['load_id'],
              'load_number': load['load_number'],
            },
      ],
  };
  Future<void> _exportAs(String format) async {
    try {
      final name = 'Material_Loads_${StaffLoadService.date(_from)}';
      final data = format == 'json'
          ? {..._data, 'period': _exportData()['period']}
          : _exportData();
      if (format == 'xlsx') {
        await _export.saveExcel(name, data);
      } else if (format == 'pdf') {
        await _export.printDataset(name, data);
      } else {
        await _export.saveJson(name, data);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _dates() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (r == null || !mounted) return;
    setState(() {
      _from = r.start;
      _to = r.end;
    });
    await _reload();
  }

  Widget _filter(
    String title,
    String key,
    String idKey,
    String nameKey,
    String? selected,
    ValueChanged<String?> changed,
  ) => SizedBox(
    width: 260,
    child: DropdownButtonFormField<String>(
      initialValue: selected ?? '',
      isExpanded: true,
      decoration: InputDecoration(labelText: title),
      items: [
        const DropdownMenuItem<String>(value: '', child: Text('All')),
        for (final r in StaffLoadService.rows(_context[key]))
          DropdownMenuItem(
            value: '${r[idKey]}',
            child: Text('${r[nameKey]}', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        changed(v == '' ? null : v);
        _reload();
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final costs = _loads.fold<double>(
      0,
      (s, l) => s + StaffLoadService.number(l['cost_total']),
    );
    final billed = _loads.fold<double>(
      0,
      (s, l) => s + StaffLoadService.number(l['customer_charge_total']),
    );
    final outstanding = _loads
        .expand((l) => StaffLoadService.rows(l['costs']))
        .fold<double>(
          0,
          (s, c) => s + StaffLoadService.number(c['outstanding']),
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Material Yard • Load reports'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _dates,
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    '${StaffLoadService.date(_from)} — ${StaffLoadService.date(_to)}',
                  ),
                ),
                _filter(
                  'Vehicle',
                  'vehicles',
                  'vehicle_id',
                  'registration_number',
                  _vehicle,
                  (v) => setState(() => _vehicle = v),
                ),
                _filter(
                  'Driver',
                  'drivers',
                  'driver_id',
                  'name',
                  _driver,
                  (v) => setState(() => _driver = v),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Export all filtered data',
                  onSelected: _exportAs,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'xlsx',
                      child: Text('Excel: loads, costs, payments and history'),
                    ),
                    PopupMenuItem(
                      value: 'pdf',
                      child: Text('Print complete report'),
                    ),
                    PopupMenuItem(
                      value: 'json',
                      child: Text('Complete saved data (JSON)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '${_loads.length} loads • Additional load costs ${_money(costs)} • Customer charges ${_money(billed)} before tax • Unpaid costs ${_money(outstanding)}',
          ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Monthly salary allocations are included in load costing; salary is posted once through Staff. Costs include the selected loads, including draft / cancelled records. Open a load for its status, invoice, payment references and delivery history.',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _loads.length,
                    itemBuilder: (context, i) {
                      final l = _loads[i];
                      final sale = l['sale'];
                      return Card(
                        child: ListTile(
                          title: Text(
                            '${l['load_number']} • ${l['load_date']} • ${l['direction']} • ${l['status']}',
                          ),
                          subtitle: Text(
                            '${l['product_name']} • ${l['quantity']} ${l['unit_code']}\nTruck ${l['vehicle_registration'] ?? ''} • Driver ${l['driver_name'] ?? ''}\n${l['source_name'] ?? ''} → ${l['destination_name'] ?? ''}\nCosts ${_money(StaffLoadService.number(l['cost_total']))} • Charges ${_money(StaffLoadService.number(l['customer_charge_total']))} • Invoice ${sale is Map ? sale['sale_number'] ?? '' : ''}',
                          ),
                          isThreeLine: false,
                          trailing: const Icon(Icons.visibility_outlined),
                          onTap: () => RecordPreview.show(
                            context,
                            title: 'Complete load report',
                            record: l,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
