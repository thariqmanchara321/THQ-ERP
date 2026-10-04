import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/client_session.dart';
import '../services/location_scope_service.dart';
import '../services/operational_export_service.dart';
import '../services/staff_load_service.dart';
import '../widgets/operational_form_dialog.dart';
import '../widgets/record_preview.dart';

class StaffScreen extends StatefulWidget {
  final ClientSession session;
  const StaffScreen({super.key, required this.session});
  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final _service = StaffLoadService();
  final _export = OperationalExportService();
  Map<String, dynamic> _data = const {};
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _to = DateTime.now();
  bool _busy = false;
  String? _error;
  String _query = '';
  bool get _manage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('staff.manage');
  bool get _payroll =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('staff.payroll');
  String get _tenant => widget.session.business.id;
  String? get _scope => LocationScopeService.currentForRead(widget.session);
  List<Map<String, dynamic>> get _staff =>
      StaffLoadService.rows(_data['staff']);
  String _money(dynamic value) =>
      '${widget.session.currencyCode} ${StaffLoadService.number(value).toStringAsFixed(2)}';
  Map<String, String> get _staffOptions => {
    for (final s in _staff) '${s['id']}': '${s['name']} (${s['staff_code']})',
  };
  static const _methods = {
    'cash': 'Cash',
    'bank': 'Bank transfer',
    'upi': 'UPI',
    'card': 'Card',
    'cheque': 'Cheque',
  };

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
      final data = await _service.staff(
        tenantId: _tenant,
        action: 'report',
        locationId: _scope,
        data: {
          'from': StaffLoadService.date(_from),
          'to': StaffLoadService.date(_to),
        },
      );
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range == null || !mounted) return;
    setState(() {
      _from = range.start;
      _to = range.end;
    });
    await _reload();
  }

  Future<void> _saveProfile([Map<String, dynamic>? member]) async {
    final location =
        member?['location_id']?.toString() ??
        LocationScopeService.currentForCreate(widget.session);
    final saved = await showOperationalForm(
      context,
      title: member == null ? 'Add staff member' : 'Edit staff member',
      initial: {
        'new_id': const Uuid().v4(),
        'joined_on': StaffLoadService.date(DateTime.now()),
        'base_rate': 0,
        'overtime_rate': 0,
        'active': 'true',
        ...?member,
        if (member != null) 'staff_id': member['id'],
      },
      fields: const [
        OperationalField('name', 'Full name', required: true),
        OperationalField('staff_code', 'Staff code (blank generates one)'),
        OperationalField(
          'job_role',
          'Role',
          options: {
            'staff': 'Staff',
            'driver': 'Driver',
            'loader': 'Loader',
            'supervisor': 'Supervisor',
            'accountant': 'Accountant',
            'other': 'Other',
          },
        ),
        OperationalField('phone', 'Phone'),
        OperationalField('license_number', 'Driver licence number'),
        OperationalField(
          'wage_basis',
          'Pay basis',
          options: {
            'monthly': 'Monthly salary',
            'daily': 'Daily wage',
            'hourly': 'Hourly wage',
            'per_trip': 'Per trip / load',
          },
        ),
        OperationalField(
          'base_rate',
          'Salary / wage rate',
          number: true,
          required: true,
        ),
        OperationalField(
          'overtime_rate',
          'Overtime rate per hour',
          number: true,
        ),
        OperationalField(
          'joined_on',
          'Joining date',
          date: true,
          required: true,
        ),
        OperationalField('left_on', 'Leaving date', date: true),
        OperationalField(
          'active',
          'Employment status',
          options: {'true': 'Active', 'false': 'Inactive'},
        ),
        OperationalField('emergency_contact', 'Emergency contact'),
        OperationalField('bank_name', 'Bank name'),
        OperationalField('bank_account', 'Bank account'),
        OperationalField('bank_ifsc', 'IFSC'),
        OperationalField('address', 'Address', lines: 2),
        OperationalField('notes', 'Notes', lines: 3),
      ],
      onSave: (data) async {
        await _service.staff(
          tenantId: _tenant,
          action: 'save',
          locationId: location,
          data: data,
        );
      },
    );
    if (saved == true) await _reload();
  }

  Future<void> _transaction(
    String action, [
    Map<String, dynamic>? selected,
  ]) async {
    if (_staff.isEmpty) {
      await _saveProfile();
      return;
    }
    if (selected == null && _staff.length > 1) {
      Map<String, dynamic>? chosen;
      final accepted = await showOperationalForm(
        context,
        title: 'Choose staff member',
        initial: {'staff_id': _staff.first['id']},
        fields: [
          OperationalField('staff_id', 'Staff member', options: _staffOptions),
        ],
        saveLabel: 'Continue',
        onSave: (d) async {
          chosen = _staff.firstWhere((s) => s['id'] == d['staff_id']);
        },
      );
      if (accepted != true || !mounted) return;
      selected = chosen;
    }
    final member = selected ?? _staff.first;
    final attendance = StaffLoadService.rows(_data['attendance'])
        .where((r) => r['staff_id'] == member['id'])
        .toList();
    final basis = member['wage_basis'];
    final units = basis == 'monthly'
        ? 1.0
        : attendance.fold<double>(
            0,
            (sum, a) =>
                sum +
                (basis == 'hourly'
                    ? StaffLoadService.number(a['hours'])
                    : a['status'] == 'half_day'
                    ? .5
                    : ['present', 'paid_leave'].contains(a['status'])
                    ? 1
                    : 0),
          );
    final overtime =
        attendance.fold<double>(
          0,
          (sum, a) => sum + StaffLoadService.number(a['overtime_hours']),
        ) *
        StaffLoadService.number(member['overtime_rate']);
    final fields = <OperationalField>[
      OperationalField(
        'staff_id',
        'Staff member',
        options: {'${member['id']}': '${member['name']}'},
      ),
      OperationalField(
        'location_id',
        'Posting location',
        options: {
          for (final loc in LocationScopeService.writableLocations(
            widget.session,
          ))
            loc.id: loc.name,
        },
      ),
      const OperationalField('date', 'Date', required: true, date: true),
      if (action == 'attendance') ...const [
        OperationalField(
          'status',
          'Attendance',
          options: {
            'present': 'Present',
            'half_day': 'Half day',
            'absent': 'Absent',
            'paid_leave': 'Paid leave',
            'unpaid_leave': 'Unpaid leave',
          },
        ),
        OperationalField('hours', 'Hours worked', number: true),
        OperationalField('overtime_hours', 'Overtime hours', number: true),
      ],
      if (action == 'payroll') ...const [
        OperationalField(
          'kind',
          'Earning type',
          options: {
            'payroll': 'Salary / wages for period',
            'bonus': 'Additional bonus',
          },
        ),
        OperationalField(
          'period_from',
          'Period from',
          required: true,
          date: true,
        ),
        OperationalField('period_to', 'Period to', required: true, date: true),
        OperationalField(
          'units',
          'Payable months / days / hours',
          required: true,
          number: true,
          help: 'Suggested from this staff member and selected attendance period. Check when changing staff.',
        ),
        OperationalField(
          'rate',
          'Rate per payable unit',
          required: true,
          number: true,
        ),
        OperationalField(
          'allowances',
          'Allowances including overtime',
          number: true,
        ),
        OperationalField('deductions', 'Agreed deductions', number: true),
      ],
      if (action == 'payment') ...const [
        OperationalField(
          'amount',
          'Payment amount',
          required: true,
          number: true,
          help: 'Settles oldest unpaid earnings in this location. Excess becomes an advance.',
        ),
        OperationalField('payment_method', 'Payment method', options: _methods),
        OperationalField('reference', 'Payment / transaction reference'),
      ],
      const OperationalField('notes', 'Notes', lines: 3),
    ];
    final saved = await showOperationalForm(
      context,
      title: switch (action) {
        'attendance' => 'Record attendance',
        'payroll' => 'Post salary / wages',
        _ => 'Pay staff / advance',
      },
      fields: fields,
      initial: {
        'staff_id': member['id'],
        'location_id':
            member['location_id'] ??
            LocationScopeService.currentForCreate(widget.session),
        'request_id': const Uuid().v4(),
        'date': StaffLoadService.date(DateTime.now()),
        'period_from': StaffLoadService.date(_from),
        'period_to': StaffLoadService.date(_to),
        'units': units,
        'rate': member['base_rate'],
        'allowances': overtime,
        'deductions': 0,
        'hours': 8,
        'overtime_hours': 0,
      },
      saveLabel: action == 'payroll' ? 'Post earning' : 'Save',
      preview: action == 'payroll'
          ? (d) =>
                'Net earning: ${_money(StaffLoadService.number(d['units']) * StaffLoadService.number(d['rate']) + StaffLoadService.number(d['allowances']) - StaffLoadService.number(d['deductions']))}. Available advances are applied automatically.'
          : null,
      onSave: (data) async {
        await _service.staff(
          tenantId: _tenant,
          action: action,
          locationId: data['location_id']?.toString(),
          data: data,
        );
      },
    );
    if (saved == true) await _reload();
  }

  Future<void> _statement(Map<String, dynamic> member) async {
    try {
      final data = await _service.staff(
        tenantId: _tenant,
        action: 'detail',
        locationId: _scope,
        data: {
          'staff_id': member['id'],
          'from': StaffLoadService.date(_from),
          'to': StaffLoadService.date(_to),
        },
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${member['name']} • Statement'),
          content: SizedBox(
            width: 820,
            child: SingleChildScrollView(child: RecordPreview(record: data)),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  _runExport('Staff_${member['staff_code']}', data, 'pdf'),
              child: const Text('Print statement / payslips'),
            ),
            TextButton(
              onPressed: () =>
                  _runExport('Staff_${member['staff_code']}', data, 'json'),
              child: const Text('Save complete record'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _runExport(
    String name,
    Map<String, dynamic> data,
    String format,
  ) async {
    try {
      data = {
        'period': {
          'from': StaffLoadService.date(_from),
          'to': StaffLoadService.date(_to),
          'location': LocationScopeService.scopeLabel(widget.session),
        },
        ...data,
      };
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

  Widget _records(String key) {
    final rows = StaffLoadService.rows(_data[key])
        .where((r) => '$r'.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    if (rows.isEmpty) {
      return const Center(child: Text('No records in this period.'));
    }
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return Card(
          child: ListTile(
            title: Text(
              '${row['staff_name'] ?? ''} • ${row['work_date'] ?? row['earning_date'] ?? row['payment_date'] ?? ''}',
            ),
            subtitle: Text(
              key == 'attendance'
                  ? '${row['status']} • ${row['hours']} hours • Overtime ${row['overtime_hours']} hours'
                  : key == 'earnings'
                  ? '${row['kind']} • ${_money(row['amount'])} • Paid ${_money(row['paid_amount'])} • Due ${_money(row['outstanding'])}'
                  : '${_money(row['amount'])} • ${row['payment_method']} • Advance ${_money(row['advance_amount'])}',
            ),
            trailing: const Icon(Icons.visibility_outlined),
            onTap: () => RecordPreview.show(
              context,
              title:
                  'Saved ${key == 'earnings' ? 'earning / payslip' : key} record',
              record: row,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Staff'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: 'Staff & balances'),
            Tab(text: 'Attendance'),
            Tab(text: 'Earnings / payroll'),
            Tab(text: 'Payments / advances'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _dates,
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    '${StaffLoadService.date(_from)} — ${StaffLoadService.date(_to)}',
                  ),
                ),
                if (_manage)
                  FilledButton.icon(
                    onPressed: _busy ? null : _saveProfile,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add staff'),
                  ),
                if (_manage)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _transaction('attendance'),
                    child: const Text('Attendance'),
                  ),
                if (_payroll)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _transaction('payroll'),
                    child: const Text('Post salary / wages'),
                  ),
                if (_payroll)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _transaction('payment'),
                    child: const Text('Pay / advance'),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Export records',
                  onSelected: (f) => _runExport(
                    'Staff_${StaffLoadService.date(_from)}',
                    _data,
                    f,
                  ),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'xlsx', child: Text('Excel report')),
                    PopupMenuItem(
                      value: 'pdf',
                      child: Text('Print full report'),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search staff and records',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Balances are current. Attendance, earnings and payments follow the selected period. Per-trip wages are recorded on loads; monthly salary allocations on loads do not post salary twice.',
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
                : TabBarView(
                    children: [
                      ListView(
                        children: _staff
                            .where(
                              (s) => '$s'.toLowerCase().contains(
                                _query.toLowerCase(),
                              ),
                            )
                            .map(
                              (s) => Card(
                                child: ListTile(
                                  title: Text(
                                    '${s['name']} • ${s['staff_code']} ${s['active'] == true ? '' : '(inactive)'}',
                                  ),
                                  subtitle: Text(
                                    '${s['job_role']} • ${s['wage_basis']} ${_money(s['base_rate'])}\nDue ${_money(s['outstanding'])} • Advance available ${_money(s['advance_balance'])} • ${s['phone'] ?? ''}',
                                  ),
                                  isThreeLine: true,
                                  onTap: () => _statement(s),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'edit') {
                                        _saveProfile(s);
                                      } else {
                                        _transaction(v, s);
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      if (_manage)
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit profile'),
                                        ),
                                      if (_manage)
                                        const PopupMenuItem(
                                          value: 'attendance',
                                          child: Text('Record attendance'),
                                        ),
                                      if (_payroll)
                                        const PopupMenuItem(
                                          value: 'payroll',
                                          child: Text('Post earning'),
                                        ),
                                      if (_payroll)
                                        const PopupMenuItem(
                                          value: 'payment',
                                          child: Text('Pay / advance'),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      _records('attendance'),
                      _records('earnings'),
                      _records('payments'),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}
