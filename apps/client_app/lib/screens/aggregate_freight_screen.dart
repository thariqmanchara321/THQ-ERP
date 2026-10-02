import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/aggregate_yard_service.dart';
import '../services/location_scope_service.dart';

class AggregateFreightScreen extends StatefulWidget {
  final ClientSession session;

  const AggregateFreightScreen({super.key, required this.session});

  @override
  State<AggregateFreightScreen> createState() => _AggregateFreightScreenState();
}

class _AggregateFreightScreenState extends State<AggregateFreightScreen> {
  final AggregateYardService _service = AggregateYardService();
  final TextEditingController _search = TextEditingController();

  Map<String, dynamic> _context = const {};
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;

  String? get _locationId => LocationScopeService.selectedLocationId.value;

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('aggregate_yard.manage') ||
      widget.session.hasPermission('aggregate_yard.freight.manage');

  bool get _canSettle => _canManage && _context['can_settle_expense'] == true;

  List<Map<String, dynamic>> _contextRows(String key) =>
      (_context[key] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);

  double _number(dynamic value) =>
      (value as num?)?.toDouble() ??
      double.tryParse(value?.toString() ?? '') ??
      0;

  String? _id(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? null : text;
  }

  String _qty(dynamic value) {
    final number = _number(value);
    if ((number - number.roundToDouble()).abs() < 0.000001) {
      return number.toStringAsFixed(0);
    }
    return number.toStringAsFixed(2);
  }

  String _money(dynamic value) {
    final amount = _number(value);
    if (widget.session.currencyCode == 'INR') {
      return '₹${amount.toStringAsFixed(2)}';
    }
    return '${widget.session.currencyCode} ${amount.toStringAsFixed(2)}';
  }

  String _label(String value) => value
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  @override
  void initState() {
    super.initState();
    _reload(all: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload({bool all = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      if (all || _context.isEmpty) {
        _context = await _service.freightContext(
          tenantId: widget.session.business.id,
        );
      }

      _rows = await _service.freightLoads(
        tenantId: widget.session.business.id,
        locationId: _locationId,
        query: _search.text.trim(),
      );
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _committedTotal =>
      _rows.fold<double>(0.0, (sum, row) => sum + _number(row['freight_cost']));

  double get _settledTotal => _rows.fold<double>(
    0.0,
    (sum, row) => sum + _number(row['freight_settled_base']),
  );

  double get _pendingTotal => _rows.fold<double>(
    0.0,
    (sum, row) => sum + _number(row['freight_pending_base']),
  );

  double? get _contributionTotal {
    final values = _rows
        .map((row) => row['contribution_after_freight'])
        .where((value) => value != null)
        .map(_number)
        .toList();
    if (values.isEmpty) return null;
    return values.fold<double>(0.0, (sum, value) => sum + value);
  }

  Future<void> _configure(Map<String, dynamic> row) async {
    if (!_canManage) return;

    String mode = (row['freight_mode'] ?? 'none').toString();
    String? transporterId = _id(row['transporter_supplier_id']);
    final amount = TextEditingController(
      text: _number(row['freight_cost']).toStringAsFixed(2),
    );
    final note = TextEditingController();

    final transporters = _contextRows('transporters');

    try {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: Text('Freight • ${row['load_number'] ?? ''}'),
            content: SizedBox(
              width: 580,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${row['product_name'] ?? ''} • '
                      '${_qty(row['quantity'])} ${row['unit_code'] ?? ''}'
                      '${_id(row['vehicle_registration']) == null ? '' : ' • ${row['vehicle_registration']}'}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: mode,
                    decoration: const InputDecoration(
                      labelText: 'Freight mode',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('None')),
                      DropdownMenuItem(
                        value: 'own',
                        child: Text('Own vehicle'),
                      ),
                      DropdownMenuItem(
                        value: 'hired',
                        child: Text('Hired transporter'),
                      ),
                      DropdownMenuItem(
                        value: 'supplier',
                        child: Text('Supplier delivery'),
                      ),
                      DropdownMenuItem(
                        value: 'customer',
                        child: Text('Customer vehicle'),
                      ),
                      DropdownMenuItem(
                        value: 'included',
                        child: Text('Included in selling rate'),
                      ),
                    ],
                    onChanged: (value) {
                      setLocalState(() {
                        mode = value ?? 'none';
                        if (mode != 'hired') transporterId = null;
                      });
                    },
                  ),
                  if (mode == 'hired') ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: transporterId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Transporter',
                        helperText:
                            'Transporters use the existing THQ Supplier master.',
                      ),
                      items: transporters
                          .map(
                            (supplier) => DropdownMenuItem<String>(
                              value: supplier['supplier_id']?.toString(),
                              child: Text(
                                '${supplier['name'] ?? ''}'
                                '${(supplier['phone'] ?? '').toString().trim().isEmpty ? '' : ' • ${supplier['phone']}'}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setLocalState(() => transporterId = value),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Committed freight cost',
                      helperText:
                          'Cost before recoverable tax. Already settled: '
                          '${_money(row['freight_settled_base'])}',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Change note'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final freight = double.tryParse(amount.text.trim()) ?? -1;
                  if (freight < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Freight cost cannot be negative.'),
                      ),
                    );
                    return;
                  }

                  if (mode == 'hired' &&
                      freight > .005 &&
                      transporterId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Select a transporter for hired freight.',
                        ),
                      ),
                    );
                    return;
                  }

                  try {
                    await _service.configureFreight(
                      tenantId: widget.session.business.id,
                      loadId: row['load_id'].toString(),
                      freightMode: mode,
                      transporterSupplierId: transporterId,
                      freightAmount: freight,
                      note: note.text,
                    );

                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop(true);
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                },
                child: const Text('Save Freight'),
              ),
            ],
          ),
        ),
      );

      if (saved == true) await _reload();
    } finally {
      amount.dispose();
      note.dispose();
    }
  }

  Future<void> _settle(Map<String, dynamic> row) async {
    if (!_canSettle) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Freight settlement requires the THQ Expenses module and '
            'Expenses Manage permission.',
          ),
        ),
      );
      return;
    }

    final categories = _contextRows('expense_categories');
    final methods = (_context['payment_methods'] as List? ?? const [])
        .map((value) => value.toString())
        .toList();

    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Create an Expense Category such as Transport / Freight first.',
          ),
        ),
      );
      return;
    }

    String? categoryId = categories.first['category_id']?.toString();
    String paymentMethod = methods.contains('bank')
        ? 'bank'
        : methods.isEmpty
        ? 'cash'
        : methods.first;
    DateTime settlementDate = DateTime.now();

    final amount = TextEditingController(
      text: _number(row['freight_pending_base']).toStringAsFixed(2),
    );
    final tax = TextEditingController(text: '0.00');
    final roundOff = TextEditingController(text: '0.00');
    final reference = TextEditingController();
    final note = TextEditingController();

    try {
      final posted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) {
            Future<void> pickDate() async {
              final value = await showDatePicker(
                context: context,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 30)),
                initialDate: settlementDate,
              );
              if (value != null) {
                setLocalState(() => settlementDate = value);
              }
            }

            return AlertDialog(
              title: Text('Settle Freight • ${row['load_number'] ?? ''}'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: .45),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${row['transporter_name'] ?? 'Transporter'} • '
                          'Committed ${_money(row['freight_cost'])} • '
                          'Paid ${_money(row['freight_settled_base'])} • '
                          'Pending ${_money(row['freight_pending_base'])}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: categoryId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Expense category',
                              ),
                              items: categories
                                  .map(
                                    (category) => DropdownMenuItem<String>(
                                      value: category['category_id']
                                          ?.toString(),
                                      child: Text(
                                        '${category['name'] ?? ''}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setLocalState(() => categoryId = value),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: pickDate,
                            icon: const Icon(Icons.event_outlined, size: 16),
                            label: Text(
                              '${settlementDate.day.toString().padLeft(2, '0')}/'
                              '${settlementDate.month.toString().padLeft(2, '0')}/'
                              '${settlementDate.year}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: amount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Freight amount',
                                helperText: 'Before recoverable tax',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: tax,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Tax amount',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: roundOff,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Round off',
                                helperText: '-1.00 to 1.00',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: paymentMethod,
                        decoration: const InputDecoration(
                          labelText: 'Payment method',
                        ),
                        items: methods
                            .map(
                              (method) => DropdownMenuItem(
                                value: method,
                                child: Text(_label(method)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setLocalState(
                          () => paymentMethod = value ?? paymentMethod,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: reference,
                        decoration: const InputDecoration(
                          labelText: 'Payment reference',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: note,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Settlement note',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withValues(alpha: .35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Posting this settlement creates a normal THQ Expense '
                          'and accounting journal. It does not create a separate '
                          'Aggregate payable.',
                          style: TextStyle(fontSize: 9.5, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final base = double.tryParse(amount.text.trim()) ?? 0;
                    final taxValue = double.tryParse(tax.text.trim()) ?? 0;
                    final roundValue =
                        double.tryParse(roundOff.text.trim()) ?? 0;
                    final pending = _number(row['freight_pending_base']);

                    if (categoryId == null) return;
                    if (base <= 0 || base > pending + .005) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Settlement must be above zero and no more than '
                            '${_money(pending)}.',
                          ),
                        ),
                      );
                      return;
                    }

                    if (taxValue < 0 || roundValue.abs() > 1) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Tax cannot be negative and round off must be '
                            'between -1.00 and 1.00.',
                          ),
                        ),
                      );
                      return;
                    }

                    final requestId =
                        'aggregate-freight:${row['load_id']}:'
                        '${DateTime.now().microsecondsSinceEpoch}';

                    try {
                      final result = await _service.settleFreight(
                        tenantId: widget.session.business.id,
                        loadId: row['load_id'].toString(),
                        categoryId: categoryId!,
                        settlementDate: settlementDate,
                        amount: base,
                        taxAmount: taxValue,
                        roundOff: roundValue,
                        paymentMethod: paymentMethod,
                        referenceNumber: reference.text,
                        note: note.text,
                        deviceId: widget.session.device?.deviceId,
                        requestId: requestId,
                      );

                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop(true);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Freight settled through '
                              '${result['expense_number'] ?? 'THQ Expense'}.',
                            ),
                          ),
                        );
                      }
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error.toString())));
                    }
                  },
                  child: const Text('Post Settlement'),
                ),
              ],
            );
          },
        ),
      );

      if (posted == true) await _reload(all: true);
    } finally {
      amount.dispose();
      tax.dispose();
      roundOff.dispose();
      reference.dispose();
      note.dispose();
    }
  }

  Widget _summaryCard({
    required double width,
    required IconData icon,
    required String label,
    required String value,
    required String helper,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  helper,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final contribution = _contributionTotal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Freight & Profitability'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _reload(all: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 850;
          final summaryWidth = compact
              ? constraints.maxWidth - 24
              : (constraints.maxWidth - 54) / 4;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText:
                        'Load, material, truck, customer, transporter or order...',
                  ),
                  onSubmitted: (_) => _reload(),
                ),
              ),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              if (_error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    _error!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _summaryCard(
                      width: summaryWidth,
                      icon: Icons.local_shipping_outlined,
                      label: 'Committed Freight',
                      value: _money(_committedTotal),
                      helper: 'Operational cost on load tickets',
                    ),
                    _summaryCard(
                      width: summaryWidth,
                      icon: Icons.payments_outlined,
                      label: 'Settled Base',
                      value: _money(_settledTotal),
                      helper: 'Posted through THQ Expenses',
                    ),
                    _summaryCard(
                      width: summaryWidth,
                      icon: Icons.pending_actions_outlined,
                      label: 'Pending Freight',
                      value: _money(_pendingTotal),
                      helper: 'Hired transporter cost not yet settled',
                    ),
                    _summaryCard(
                      width: summaryWidth,
                      icon: Icons.trending_up_outlined,
                      label: 'Contribution',
                      value: contribution == null
                          ? 'Restricted / unlinked'
                          : _money(contribution),
                      helper: 'Material gross profit less freight',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading && _rows.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _rows.isEmpty
                    ? const Center(
                        child: Text('No Aggregate loads to show yet.'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final row = _rows[index];
                          final direction = row['direction']?.toString() ?? '';
                          final freightStatus =
                              row['freight_status']?.toString() ??
                              'not_required';
                          final saleVisible =
                              row['sale_financials_visible'] == true;
                          final purchaseVisible =
                              row['purchase_financials_visible'] == true;
                          final pending = _number(row['freight_pending_base']);

                          return Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        direction == 'inbound'
                                            ? Icons.south_west_rounded
                                            : Icons.north_east_rounded,
                                        size: 18,
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          '${row['load_number'] ?? ''} • '
                                          '${row['product_name'] ?? ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      Chip(
                                        visualDensity: VisualDensity.compact,
                                        label: Text(
                                          _label(freightStatus),
                                          style: const TextStyle(fontSize: 8.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_qty(row['quantity'])} '
                                    '${row['unit_code'] ?? ''}'
                                    '${_id(row['vehicle_registration']) == null ? '' : ' • ${row['vehicle_registration']}'}'
                                    '${_id(row['order_number']) == null ? '' : ' • ${row['order_number']}'}',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 9),
                                  Wrap(
                                    spacing: 18,
                                    runSpacing: 7,
                                    children: [
                                      _Info(
                                        label: 'Mode',
                                        value: _label(
                                          row['freight_mode']?.toString() ??
                                              'none',
                                        ),
                                      ),
                                      _Info(
                                        label: 'Transporter',
                                        value:
                                            _id(row['transporter_name']) ?? '—',
                                      ),
                                      _Info(
                                        label: 'Freight Cost',
                                        value: _money(row['freight_cost']),
                                      ),
                                      _Info(
                                        label: 'Settled',
                                        value: _money(
                                          row['freight_settled_base'],
                                        ),
                                      ),
                                      _Info(
                                        label: 'Pending',
                                        value: _money(pending),
                                      ),
                                    ],
                                  ),
                                  if ((direction == 'outbound' ||
                                          direction == 'direct_delivery') &&
                                      saleVisible) ...[
                                    const Divider(height: 20),
                                    Wrap(
                                      spacing: 18,
                                      runSpacing: 7,
                                      children: [
                                        _Info(
                                          label: 'Material Revenue',
                                          value: row['material_revenue'] == null
                                              ? 'Sale not linked'
                                              : _money(row['material_revenue']),
                                        ),
                                        _Info(
                                          label: 'Material COGS',
                                          value: row['material_cost'] == null
                                              ? '—'
                                              : _money(row['material_cost']),
                                        ),
                                        _Info(
                                          label: 'Gross Profit',
                                          value:
                                              row['material_gross_profit'] ==
                                                  null
                                              ? '—'
                                              : _money(
                                                  row['material_gross_profit'],
                                                ),
                                        ),
                                        _Info(
                                          label: 'After Freight',
                                          value:
                                              row['contribution_after_freight'] ==
                                                  null
                                              ? '—'
                                              : _money(
                                                  row['contribution_after_freight'],
                                                ),
                                        ),
                                      ],
                                    ),
                                    if (_number(
                                          row['sale_unclassified_additional_charges'],
                                        ) >
                                        .005)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 7),
                                        child: Text(
                                          'Invoice has '
                                          '${_money(row['sale_unclassified_additional_charges'])} '
                                          'of additional charges. They are shown separately '
                                          'and are not assumed to be freight revenue.',
                                          style: TextStyle(
                                            fontSize: 8.8,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                  ],
                                  if (direction == 'inbound' &&
                                      purchaseVisible) ...[
                                    const Divider(height: 20),
                                    Wrap(
                                      spacing: 18,
                                      runSpacing: 7,
                                      children: [
                                        _Info(
                                          label: 'Material Cost',
                                          value:
                                              row['purchase_material_cost'] ==
                                                  null
                                              ? 'Purchase not linked'
                                              : _money(
                                                  row['purchase_material_cost'],
                                                ),
                                        ),
                                        _Info(
                                          label: 'Landed Cost + Freight',
                                          value:
                                              row['inbound_landed_cost_after_freight'] ==
                                                  null
                                              ? '—'
                                              : _money(
                                                  row['inbound_landed_cost_after_freight'],
                                                ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (_canManage)
                                        OutlinedButton.icon(
                                          onPressed: () => _configure(row),
                                          icon: const Icon(
                                            Icons.tune_rounded,
                                            size: 15,
                                          ),
                                          label: const Text('Freight Setup'),
                                        ),
                                      if (_canManage &&
                                          row['freight_mode'] == 'hired' &&
                                          pending > .005) ...[
                                        const SizedBox(width: 8),
                                        FilledButton.icon(
                                          onPressed: () => _settle(row),
                                          icon: const Icon(
                                            Icons.payments_outlined,
                                            size: 15,
                                          ),
                                          label: const Text('Settle Freight'),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final String label;
  final String value;

  const _Info({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 8.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
