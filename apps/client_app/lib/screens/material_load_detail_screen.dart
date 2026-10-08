import 'package:thq_ui/thq_ui.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/client_session.dart';
import '../services/staff_load_service.dart';
import '../services/operational_export_service.dart';
import '../widgets/load_cost_editor.dart';
import '../widgets/operational_form_dialog.dart';
import '../widgets/record_preview.dart';
import 'staff_screen.dart';

class MaterialLoadDetailScreen extends StatefulWidget {
  final ClientSession session;
  final String loadId;
  const MaterialLoadDetailScreen({
    super.key,
    required this.session,
    required this.loadId,
  });
  @override
  State<MaterialLoadDetailScreen> createState() =>
      _MaterialLoadDetailScreenState();
}

class _MaterialLoadDetailScreenState extends State<MaterialLoadDetailScreen> {
  final _service = StaffLoadService();
  final _export = OperationalExportService();
  Map<String, dynamic> _record = const {};
  bool _busy = false;
  String? _error;
  bool get _manage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('aggregate_yard.manage');
  bool get _costManage =>
      _manage &&
      (widget.session.hasRole('owner') ||
          widget.session.hasPermission('aggregate_yard.costs'));
  String get _tenant => widget.session.business.id;
  String _money(dynamic v) =>
      '${widget.session.currencyCode} ${StaffLoadService.number(v).toStringAsFixed(2)}';
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      final data = await _service.load(
        tenantId: _tenant,
        action: 'detail',
        data: {'load_id': widget.loadId},
      );
      if (mounted) setState(() => _record = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delivery() async {
    final details = _record['delivery'];
    final data = await editLoadDelivery(
      context,
      initial: details is Map ? Map<String, dynamic>.from(details) : const {},
    );
    if (data == null) return;
    await _action('delivery', {...data, 'load_id': widget.loadId});
  }

  Future<void> _action(String action, Map<String, dynamic> data) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _service.load(tenantId: _tenant, action: action, data: data);
      await _reload();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  Future<void> _pay(Map<String, dynamic> cost) async {
    final success = await showOperationalForm(
      context,
      title: 'Pay ${cost['description']}',
      initial: {
        'request_id': const Uuid().v4(),
        'cost_id': cost['id'],
        'load_id': widget.loadId,
        'date': StaffLoadService.date(DateTime.now()),
        'amount': cost['outstanding'],
      },
      fields: const [
        OperationalField('date', 'Payment date', date: true, required: true),
        OperationalField('amount', 'Amount', number: true, required: true),
        OperationalField(
          'payment_method',
          'Method',
          options: {
            'cash': 'Cash',
            'bank': 'Bank transfer',
            'upi': 'UPI',
            'card': 'Card',
            'cheque': 'Cheque',
          },
        ),
        OperationalField('reference', 'Payment reference'),
        OperationalField('notes', 'Notes', lines: 3),
      ],
      onSave: (data) async {
        await _service.load(tenantId: _tenant, action: 'payment', data: data);
      },
    );
    if (success == true) await _reload();
  }

  Future<void> _addCost() async {
    try {
      final location = _record['location_id'].toString();
      final configuration = await _service.load(
        tenantId: _tenant,
        action: 'context',
        locationId: location,
      );
      if (!mounted) return;
      var costs = <Map<String, dynamic>>[];
      final requestId = const Uuid().v4();
      var saving = false;
      String? error;
      final linked =
          _record['sale_id'] != null || _record['purchase_id'] != null;
      final success = await showThqDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (context, local) => AlertDialog(
            title: Text(linked ? 'Add internal expense' : 'Add load expense'),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LoadCostEditor(
                      session: widget.session,
                      locationId: location,
                      direction: '${_record['direction']}',
                      driverId: _record['driver_id']?.toString(),
                      contextData: configuration,
                      costs: costs,
                      internalOnly: linked,
                      onChanged: (v) => local(() => costs = v),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving || costs.isEmpty
                    ? null
                    : () async {
                        local(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await _service.load(
                            tenantId: _tenant,
                            action: 'add_cost',
                            data: {
                              'load_id': widget.loadId,
                              'costs': costs,
                              'request_id': requestId,
                            },
                          );
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          if (ctx.mounted) {
                            local(() {
                              saving = false;
                              error = e.toString();
                            });
                          }
                        }
                      },
                child: Text(saving ? 'Saving…' : 'Save expenses'),
              ),
            ],
          ),
        ),
      );
      if (success == true) await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _exportRecord(String format) async {
    try {
      final name = 'Load_${_record['load_number']}';
      if (format == 'pdf') {
        await _export.printDataset(name, _record);
      } else {
        await _export.saveJson(name, _record);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final costs = StaffLoadService.rows(_record['costs']);
    final confirmed = _record['status'] == 'completed';
    final cancelled = _record['status'] == 'cancelled';
    final outbound = _record['direction'] == 'outbound';
    final linked = _record[outbound ? 'sale_id' : 'purchase_id'] != null;
    final billingPermission =
        widget.session.hasRole('owner') ||
        widget.session.hasPermission(
          '${outbound ? 'sales' : 'purchases'}.${linked ? 'view' : 'manage'}',
        );
    return Scaffold(
      appBar: AppBar(
        title: Text('${_record['load_number'] ?? 'Load details'}'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  SelectableText(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                LoadEvidenceCard(record: _record),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_manage && !confirmed && !cancelled)
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(context, 'confirm'),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Confirm & continue to invoice'),
                      ),
                    if (confirmed && billingPermission)
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(context, 'billing'),
                        icon: const Icon(Icons.receipt_long),
                        label: Text(
                          '${linked ? 'View' : 'Create'} ${outbound ? 'sale' : 'purchase'}',
                        ),
                      ),
                    if (widget.session.hasModule('vehicle_logistics') ||
                        widget.session.hasModule('logistics_operations') ||
                        widget.session.hasModule('transport_service'))
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context, 'transport'),
                        child: const Text('View linked trip'),
                      ),
                    if (_manage && !cancelled)
                      OutlinedButton(
                        onPressed: _delivery,
                        child: const Text('Update delivery details'),
                      ),
                    if (_costManage && !cancelled)
                      OutlinedButton(
                        onPressed: _addCost,
                        child: const Text('Add expense'),
                      ),
                    if (widget.session.hasModule('staff') &&
                        (widget.session.hasRole('owner') ||
                            widget.session.hasPermission('staff.view')))
                      OutlinedButton(
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                StaffScreen(session: widget.session),
                          ),
                        ),
                        child: const Text('Staff & wages'),
                      ),
                    OutlinedButton(
                      onPressed: () => _exportRecord('pdf'),
                      child: const Text('Print full load record'),
                    ),
                    OutlinedButton(
                      onPressed: () => _exportRecord('json'),
                      child: const Text('Save complete data'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Expenses & settlement',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (costs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No additional load expenses recorded.'),
                  ),
                for (final cost in costs)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${cost['description']} • ${cost['payee']}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${cost['quantity']} × ${_money(cost['rate'])} = ${_money(cost['amount'])} • ${cost['status']}',
                          ),
                          Text(
                            'Customer charge ${_money(cost['bill_amount'])} before tax • ${cost['billing_service'] ?? 'Internal expense'}',
                          ),
                          Text(
                            cost['staff_mode'] == 'salary_allocation'
                                ? 'Monthly salary allocated to this load. Salary payment is tracked through Staff payroll.'
                                : 'Paid ${_money(cost['paid_amount'])} • Outstanding ${_money(cost['outstanding'])}',
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => RecordPreview.show(
                                  context,
                                  title: 'Saved expense details',
                                  record: cost,
                                ),
                                child: const Text('Preview expense'),
                              ),
                              if (_costManage &&
                                  cost['status'] == 'posted' &&
                                  cost['staff_mode'] != 'salary_allocation' &&
                                  StaffLoadService.number(cost['outstanding']) >
                                      .005)
                                FilledButton.tonal(
                                  onPressed: () => _pay(cost),
                                  child: const Text('Record payment'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                ExpansionTile(
                  title: const Text(
                    'Delivery, payments and full saved history',
                  ),
                  children: [RecordPreview(record: _record)],
                ),
              ],
            ),
    );
  }
}
