import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/client_session.dart';
import '../services/staff_load_service.dart';
import 'operational_form_dialog.dart';
import 'record_preview.dart';

class LoadCostEditor extends StatefulWidget {
  final ClientSession session;
  final String locationId;
  final String direction;
  final String? driverId;
  final Map<String, dynamic> contextData;
  final List<Map<String, dynamic>> costs;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool internalOnly;
  const LoadCostEditor({
    super.key,
    required this.session,
    required this.locationId,
    required this.direction,
    required this.contextData,
    required this.costs,
    required this.onChanged,
    this.driverId,
    this.internalOnly = false,
  });
  @override
  State<LoadCostEditor> createState() => _LoadCostEditorState();
}

class _LoadCostEditorState extends State<LoadCostEditor> {
  List<Map<String, dynamic>>? _services;
  static const kinds = {
    'driver_wage': 'Driver wage',
    'staff_wage': 'Staff wage',
    'vehicle_rent': 'Vehicle rent',
    'diesel': 'Diesel / fuel',
    'loading': 'Loading / unloading',
    'toll': 'Toll',
    'freight': 'Freight',
    'other': 'Other expense',
  };
  List<Map<String, dynamic>> get _staff =>
      StaffLoadService.rows(widget.contextData['staff'])
          .where(
            (s) =>
                s['location_id'] == null ||
                s['location_id'] == widget.locationId,
          )
          .toList();
  List<Map<String, dynamic>> get _billing =>
      _services ??
      StaffLoadService.rows(widget.contextData['billing_services']);
  String _money(dynamic value) =>
      '${widget.session.currencyCode} ${StaffLoadService.number(value).toStringAsFixed(2)}';
  Future<void> _newService() async {
    final saved = await showOperationalForm(
      context,
      title: 'Create customer charge service',
      initial: {'new_id': const Uuid().v4(), 'gst_rate': 0},
      fields: [
        const OperationalField('name', 'Service name', required: true),
        const OperationalField('description', 'Description', lines: 2),
        if (widget.contextData['tax_mode'] == 'gst_registered') ...const [
          OperationalField(
            'hsn_sac',
            'Correct SAC for this service',
            required: true,
            help:
                'Use the classification applicable to the service being supplied.',
          ),
          OperationalField(
            'taxability',
            'Tax treatment',
            options: {
              'taxable': 'Taxable',
              'nil_rated': 'Nil rated',
              'exempt': 'Exempt',
              'non_gst': 'Outside GST',
            },
          ),
          OperationalField(
            'gst_rate',
            'GST rate (%)',
            number: true,
            required: true,
          ),
        ],
      ],
      onSave: (data) async {
        await StaffLoadService().load(
          tenantId: widget.session.business.id,
          locationId: widget.locationId,
          action: 'billing_service',
          data: data,
        );
      },
    );
    if (saved != true) return;
    final data = await StaffLoadService().load(
      tenantId: widget.session.business.id,
      locationId: widget.locationId,
      action: 'context',
    );
    if (mounted) {
      setState(
        () => _services = StaffLoadService.rows(data['billing_services']),
      );
    }
  }

  Future<void> _edit([int? index]) async {
    Map<String, dynamic>? driver;
    for (final s in _staff) {
      if (s['driver_id'] == widget.driverId && widget.driverId != null) {
        driver = s;
        break;
      }
    }
    final old = index == null ? null : widget.costs[index];
    final salary = driver?['wage_basis'] == 'monthly';
    final saved = <String, dynamic>{};
    final success = await showOperationalForm(
      context,
      title: old == null ? 'Add load expense' : 'Edit load expense',
      initial: {
        'id': const Uuid().v4(),
        'cost_kind': driver == null ? 'other' : 'driver_wage',
        'quantity': 1,
        'rate': salary ? 0 : driver?['base_rate'] ?? 0,
        'staff_id': driver?['staff_id'] ?? '',
        'staff_mode': salary ? 'salary_allocation' : 'extra_wage',
        'description': driver == null ? '' : 'Driver wage',
        'payee': driver?['name'] ?? '',
        'bill_amount': 0,
        'initial_payment': 0,
        ...?old,
      },
      fields: [
        const OperationalField('cost_kind', 'Expense type', options: kinds),
        const OperationalField(
          'description',
          'Expense / invoice description',
          required: true,
        ),
        OperationalField(
          'staff_id',
          'Staff payee (optional)',
          options: {
            '': 'External payee / supplier',
            for (final s in _staff)
              '${s['staff_id']}':
                  '${s['name']} • ${s['wage_basis']} ${_money(s['base_rate'])}',
          },
        ),
        const OperationalField(
          'payee',
          'External payee name',
          help:
              'Required for an external payee. Linked staff names are saved automatically.',
        ),
        const OperationalField(
          'staff_mode',
          'Staff wage treatment',
          options: {
            'extra_wage': 'Additional wage owed to staff',
            'salary_allocation': 'Allocate monthly salary to this load',
          },
          help:
              'Salary allocation tracks load cost without posting monthly payroll again. Choose additional wage when it is extra pay.',
        ),
        const OperationalField(
          'quantity',
          'Expense units / trips',
          required: true,
          number: true,
        ),
        const OperationalField(
          'rate',
          'Cost per unit (editable)',
          required: true,
          number: true,
        ),
        if (widget.direction == 'outbound' && !widget.internalOnly) ...[
          const OperationalField(
            'bill_amount',
            'Amount charged to customer before GST',
            number: true,
            help:
                'Zero keeps this as an internal expense. This amount may differ from your cost.',
          ),
          OperationalField(
            'billing_variant_id',
            'Invoice service / tax classification',
            options: {
              '': 'Select when charging customer',
              for (final s in _billing)
                '${s['variant_id']}':
                    '${s['name']} • GST ${s['gst_rate'] ?? s['tax_rate'] ?? 0}%',
            },
          ),
        ],
        const OperationalField(
          'initial_payment',
          'Pay on load confirmation',
          number: true,
          help:
              'Zero leaves the expense unpaid. Salary allocations are paid through Staff payroll.',
        ),
        const OperationalField(
          'payment_method',
          'Payment method',
          options: {
            'cash': 'Cash',
            'bank': 'Bank',
            'upi': 'UPI',
            'card': 'Card',
            'cheque': 'Cheque',
          },
        ),
        const OperationalField('payment_reference', 'Payment reference'),
        const OperationalField('receipt_reference', 'Bill / receipt reference'),
        const OperationalField('notes', 'Notes', lines: 3),
      ],
      preview: (d) =>
          'Load cost: ${_money(StaffLoadService.number(d['quantity']) * StaffLoadService.number(d['rate']))} • Customer charge: ${_money(d['bill_amount'])} before tax',
      onSave: (d) async {
        final amount =
            StaffLoadService.number(d['quantity']) *
            StaffLoadService.number(d['rate']);
        if (amount <= 0) {
          throw StateError('Enter a positive expense quantity and rate.');
        }
        if (d['staff_id'] == '' &&
            (d['payee']?.toString().trim().isEmpty ?? true)) {
          throw StateError('Enter the external payee name.');
        }
        if (d['staff_id'] != '' &&
            !['driver_wage', 'staff_wage'].contains(d['cost_kind'])) {
          throw StateError(
            'Linked staff require a driver or staff wage expense type.',
          );
        }
        if (d['staff_mode'] == 'salary_allocation' &&
            (d['staff_id'] == '' ||
                StaffLoadService.number(d['initial_payment']) > 0)) {
          throw StateError(
            'Salary allocation requires monthly staff and no separate payment on this load.',
          );
        }
        if (StaffLoadService.number(d['bill_amount']) > 0 &&
            (d['billing_variant_id']?.toString().isEmpty ?? true)) {
          throw StateError(
            'Select or create the service used to invoice this charge.',
          );
        }
        if (StaffLoadService.number(d['initial_payment']) > amount) {
          throw StateError('Payment cannot exceed this expense.');
        }
        if (StaffLoadService.number(d['initial_payment']) > 0 &&
            d['payment_method'] != 'cash' &&
            (d['payment_reference']?.toString().trim().isEmpty ?? true)) {
          throw StateError('Enter the payment reference.');
        }
        saved.addAll({
          ...d,
          'amount': amount,
          if (widget.internalOnly || widget.direction != 'outbound')
            'bill_amount': 0,
        });
      },
    );
    if (success == true) {
      final next = [...widget.costs];
      if (index == null) {
        next.add(saved);
      } else {
        next[index] = saved;
      }
      widget.onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Load expenses & customer charges',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'Record driver wages, rent, fuel and other costs here. Costs and any payments post together when you confirm the load. Customer charges are added to its invoice using the selected service tax classification.',
          ),
          for (var i = 0; i < widget.costs.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${widget.costs[i]['description']} • ${_money(widget.costs[i]['amount'])}',
              ),
              subtitle: Text(
                '${widget.costs[i]['payee'] ?? ''} • ${widget.costs[i]['staff_mode'] == 'salary_allocation' ? 'Monthly salary allocation' : 'Additional cost'} • Bill customer ${_money(widget.costs[i]['bill_amount'])}',
              ),
              onTap: () => _edit(i),
              trailing: IconButton(
                tooltip: 'Remove draft expense',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () {
                  final next = [...widget.costs]..removeAt(i);
                  widget.onChanged(next);
                },
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Add expense'),
              ),
              if (widget.direction == 'outbound' &&
                  !widget.internalOnly &&
                  widget.contextData['can_create_billing_service'] == true)
                TextButton(
                  onPressed: _newService,
                  child: const Text('Create invoice charge service'),
                ),
            ],
          ),
          Text(
            'Total cost ${_money(widget.costs.fold<double>(0, (sum, c) => sum + StaffLoadService.number(c['amount'])))} • Customer charges ${_money(widget.costs.fold<double>(0, (sum, c) => sum + StaffLoadService.number(c['bill_amount'])))} before tax',
          ),
        ],
      ),
    ),
  );
}

Future<Map<String, dynamic>?> editLoadDelivery(
  BuildContext context, {
  Map<String, dynamic> initial = const {},
}) async {
  Map<String, dynamic>? saved;
  await showOperationalForm(
    context,
    title: 'Driver & delivery details',
    initial: initial,
    fields: const [
      OperationalField('driver_contact_name', 'Driver / contact name'),
      OperationalField('driver_contact_phone', 'Driver phone'),
      OperationalField('driver_license_snapshot', 'Driver licence number'),
      OperationalField('pickup_address', 'Pickup address', lines: 2),
      OperationalField('delivery_address', 'Delivery address', lines: 2),
      OperationalField('pickup_contact', 'Pickup contact'),
      OperationalField('delivery_contact', 'Delivery contact'),
      OperationalField(
        'dispatch_at',
        'Departure date and time',
        help: 'Example: 2026-10-04T09:30:00+05:30',
      ),
      OperationalField('delivered_at', 'Delivered date and time'),
      OperationalField('odometer_start', 'Start odometer (km)', number: true),
      OperationalField('odometer_end', 'End odometer (km)', number: true),
      OperationalField('delivery_latitude', 'Delivery latitude'),
      OperationalField('delivery_longitude', 'Delivery longitude'),
      OperationalField('received_by', 'Received by'),
      OperationalField('proof_reference', 'Delivery proof / reference'),
      OperationalField(
        'delivery_notes',
        'Delivery instructions / notes',
        lines: 3,
      ),
    ],
    onSave: (d) async {
      saved = d;
    },
  );
  return saved;
}

class LoadEvidenceCard extends StatelessWidget {
  final Map<String, dynamic> record;
  const LoadEvidenceCard({super.key, required this.record});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Load ${record['load_number'] ?? ''}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            'Vehicle: ${record['vehicle_registration'] ?? record['vehicle_registration_snapshot'] ?? 'Not assigned'} • Driver: ${record['driver_name'] ?? record['driver_name_snapshot'] ?? 'Not assigned'}',
          ),
          Text(
            '${record['source_name'] ?? ''} → ${record['destination_name'] ?? ''} • ${record['location_name'] ?? ''}',
          ),
          Text(
            'Load cost: ${StaffLoadService.number(record['cost_total']).toStringAsFixed(2)} • Customer charges: ${StaffLoadService.number(record['customer_charge_total']).toStringAsFixed(2)} before tax',
          ),
          TextButton(
            onPressed: () => RecordPreview.show(
              context,
              title: 'All saved load, cost, driver and delivery details',
              record: record,
            ),
            child: const Text('Preview all saved details'),
          ),
        ],
      ),
    ),
  );
}
