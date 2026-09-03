import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/inventory_product.dart';
import '../services/inventory_service.dart';
import '../services/location_scope_service.dart';
import '../services/stock_transfer_service.dart';

class StockTransfersScreen extends StatefulWidget {
  final ClientSession session;
  const StockTransfersScreen({super.key, required this.session});

  @override
  State<StockTransfersScreen> createState() => _StockTransfersScreenState();
}

class _StockTransfersScreenState extends State<StockTransfersScreen> {
  final StockTransferService _service = StockTransferService();
  late Future<List<Map<String, dynamic>>> _transfers;
  late Future<List<Map<String, dynamic>>> _warehouses;
  late Future<List<Map<String, dynamic>>> _counts;
  late Future<List<Map<String, dynamic>>> _reconciliation;
  bool _onlyVariance = false;

  String get _tenantId => widget.session.business.id;

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('inventory.transfer') ||
      widget.session.hasPermission('inventory.manage');

  bool get _canApprove =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('inventory.manage') ||
      widget.session.hasPermission('approvals.approve');

  bool get _canCount =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('inventory.stock_count') ||
      widget.session.hasPermission('inventory.manage');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  String? get _scopeLocationId => LocationScopeService.selectedLocationId.value;

  void _reload() {
    _transfers = _service.list(
      tenantId: _tenantId,
      locationId: _scopeLocationId,
    );
    _warehouses = _service.warehouses(tenantId: _tenantId);
    _counts = _service.countHistory(
      tenantId: _tenantId,
      locationId: _scopeLocationId,
    );
    _reconciliation = _service.reconciliation(
      tenantId: _tenantId,
      locationId: _scopeLocationId,
      onlyVariance: _onlyVariance,
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await Future.wait([_transfers, _warehouses, _counts, _reconciliation]);
  }

  List<ClientLocationAccess> get _writableLocations {
    final rows = widget.session.locations.where((location) {
      if (widget.session.hasRole('owner') ||
          widget.session.hasPermission('locations.manage_all')) {
        return true;
      }
      return location.canOperate;
    }).toList();
    rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rows;
  }

  ClientLocationAccess? _location(String id) {
    for (final row in widget.session.locations) {
      if (row.id == id) return row;
    }
    return null;
  }

  Future<void> _createTransfer() async {
    final writable = _writableLocations;
    if (writable.isEmpty) {
      _message('You do not have operate access to a stock location.');
      return;
    }
    var fromId = _scopeLocationId;
    if (fromId == null || !writable.any((e) => e.id == fromId)) {
      fromId = widget.session.device?.locationId;
    }
    if (fromId == null || !writable.any((e) => e.id == fromId)) {
      fromId = writable.first.id;
    }
    final destinations = widget.session.locations
        .where((e) => e.id != fromId)
        .toList();
    if (destinations.isEmpty) {
      _message('Create another store/warehouse before making a transfer.');
      return;
    }
    final products = await InventoryService().getProducts(
      tenantId: _tenantId,
      locationId: fromId,
    );
    if (!mounted) return;
    if (products.isEmpty) {
      _message('No stock products are assigned to the source location.');
      return;
    }

    String sourceId = fromId;
    String toId = destinations.first.id;
    InventoryProduct product = products.first;
    Map<String, dynamic> tracking = await _service.trackingOptions(
      tenantId: _tenantId,
      locationId: sourceId,
      variantId: product.variantId,
    );
    if (!mounted) return;

    final qty = TextEditingController(text: '1');
    final serials = TextEditingController();
    final batches = TextEditingController();
    final notes = TextEditingController();
    final transport = TextEditingController();
    DateTime? expected;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> changeProduct(String? value) async {
            if (value == null) return;
            product = products.firstWhere((p) => p.variantId == value);
            serials.clear();
            batches.clear();
            final next = await _service.trackingOptions(
              tenantId: _tenantId,
              locationId: sourceId,
              variantId: product.variantId,
            );
            if (dialogContext.mounted) setDialogState(() => tracking = next);
          }

          final serialRows = (tracking['serials'] as List? ?? const [])
              .whereType<Map>()
              .toList();
          final batchRows = (tracking['batches'] as List? ?? const [])
              .whereType<Map>()
              .toList();
          return AlertDialog(
            title: const Text('Stock Transfer Request'),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ReadOnlyField(
                      label: 'Source',
                      value:
                          '${_location(sourceId)?.code ?? ''} • ${_location(sourceId)?.name ?? ''}',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: toId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Destination store / warehouse',
                      ),
                      items: destinations
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.id,
                              child: Text('${e.code} • ${e.name}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => toId = value ?? toId),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: product.variantId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Product'),
                      items: products
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.variantId,
                              child: Text(
                                '${p.productName} • ${p.sku} • Available ${p.stockQuantity.toStringAsFixed(2)}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: changeProduct,
                    ),
                    const SizedBox(height: 12),
                    if (product.trackingMode == 'none')
                      TextField(
                        controller: qty,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Quantity (${product.baseUnitCode})',
                        ),
                      ),
                    if (product.trackingMode == 'serial') ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Available serials: ${serialRows.length}',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 90),
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: serialRows
                                .take(30)
                                .map(
                                  (row) => Chip(
                                    label: Text(
                                      row['serial_number']?.toString() ?? '',
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: serials,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Serial numbers to transfer',
                          hintText:
                              'One serial per line. Quantity is the number of serials.',
                        ),
                      ),
                    ],
                    if (product.trackingMode == 'batch') ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Available batches',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...batchRows
                          .take(8)
                          .map(
                            (row) => Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${row['batch_number']} • available ${_number(row['available_quantity']).toStringAsFixed(2)}'
                                '${row['expiry_on'] == null ? '' : ' • exp ${row['expiry_on']}'}',
                              ),
                            ),
                          ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: batches,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Batch allocations',
                          hintText:
                              'One per line: BATCH-NUMBER=QTY\nExample: LOT-2401=5',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            expected == null
                                ? 'Expected arrival: not set'
                                : 'Expected arrival: ${_date(expected!)}',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 730),
                              ),
                              initialDate: expected ?? DateTime.now(),
                            );
                            if (picked != null) {
                              setDialogState(() => expected = picked);
                            }
                          },
                          icon: const Icon(Icons.event_outlined),
                          label: const Text('Set date'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: transport,
                      decoration: const InputDecoration(
                        labelText: 'Transport / vehicle reference (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notes,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Request notes (optional)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Request Transfer'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) {
      qty.dispose();
      serials.dispose();
      batches.dispose();
      notes.dispose();
      transport.dispose();
      return;
    }

    final item = <String, dynamic>{'variant_id': product.variantId};
    if (product.trackingMode == 'serial') {
      final values = _lines(serials.text);
      if (values.isEmpty) {
        _message('Enter at least one serial number.');
        return;
      }
      item['quantity'] = values.length;
      item['serial_numbers'] = values;
    } else if (product.trackingMode == 'batch') {
      final parsed = _parseBatchTransfer(batches.text);
      if (parsed.$1 == null) {
        _message(parsed.$2);
        return;
      }
      item['batches'] = parsed.$1;
      item['quantity'] = parsed.$1!.fold<double>(
        0,
        (sum, row) => sum + _number(row['quantity']),
      );
    } else {
      final amount = double.tryParse(qty.text.trim()) ?? 0;
      if (amount <= 0) {
        _message('Enter a valid transfer quantity.');
        return;
      }
      item['quantity'] = amount;
    }

    try {
      final result = await _service.create(
        tenantId: _tenantId,
        fromLocationId: sourceId,
        toLocationId: toId,
        items: [item],
        notes: notes.text,
        expectedArrival: expected,
        transportReference: transport.text,
      );
      _message(
        'Transfer ${result['transfer_number']} requested and stock reserved.',
      );
      await _refresh();
    } catch (error) {
      _message(_cleanError(error));
    } finally {
      qty.dispose();
      serials.dispose();
      batches.dispose();
      notes.dispose();
      transport.dispose();
    }
  }

  (List<Map<String, dynamic>>?, String) _parseBatchTransfer(String text) {
    final rows = <Map<String, dynamic>>[];
    for (final line in _lines(text)) {
      final split = line.split('=');
      if (split.length != 2 || split.first.trim().isEmpty) {
        return (null, 'Use batch format BATCH-NUMBER=QTY.');
      }
      final amount = double.tryParse(split[1].trim()) ?? 0;
      if (amount <= 0) {
        return (null, 'Every batch quantity must be greater than zero.');
      }
      rows.add({'batch_number': split[0].trim(), 'quantity': amount});
    }
    if (rows.isEmpty) return (null, 'Enter at least one batch allocation.');
    return (rows, '');
  }

  Future<String?> _noteDialog(String title, {bool required = false}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: required ? 'Reason (required)' : 'Note (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (required && controller.text.trim().isEmpty) return;
              Navigator.pop(dialogContext, controller.text.trim());
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<(String, String)?> _dispatchDialog() async {
    final note = TextEditingController();
    final transport = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dispatch Transfer'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: transport,
                decoration: const InputDecoration(
                  labelText: 'Vehicle / transport reference',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Dispatch note (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, (
              note.text.trim(),
              transport.text.trim(),
            )),
            icon: const Icon(Icons.local_shipping_outlined),
            label: const Text('Dispatch'),
          ),
        ],
      ),
    );
    note.dispose();
    transport.dispose();
    return result;
  }

  Future<void> _action(Map<String, dynamic> row, String action) async {
    try {
      final id = row['id'].toString();
      if (action == 'approve') {
        await _service.decide(
          tenantId: _tenantId,
          transferId: id,
          approve: true,
        );
      } else if (action == 'reject') {
        final reason = await _noteDialog('Reject Transfer', required: true);
        if (reason == null) return;
        await _service.decide(
          tenantId: _tenantId,
          transferId: id,
          approve: false,
          note: reason,
        );
      } else if (action == 'cancel') {
        final reason = await _noteDialog('Cancel Transfer');
        if (reason == null) return;
        await _service.cancel(
          tenantId: _tenantId,
          transferId: id,
          reason: reason,
        );
      } else if (action == 'dispatch') {
        final values = await _dispatchDialog();
        if (values == null) return;
        await _service.dispatch(
          tenantId: _tenantId,
          transferId: id,
          note: values.$1,
          transportReference: values.$2,
        );
      } else if (action == 'receive') {
        final note = await _noteDialog('Receive Transfer');
        if (note == null) return;
        await _service.receive(tenantId: _tenantId, transferId: id, note: note);
      }
      final labels = {
        'approve': 'Transfer approved.',
        'reject': 'Transfer rejected; reservations released.',
        'cancel': 'Transfer cancelled; reservations released.',
        'dispatch': 'Transfer dispatched and is now In Transit.',
        'receive': 'Transfer received into destination stock.',
      };
      _message(labels[action] ?? 'Transfer updated.');
      await _refresh();
    } catch (error) {
      _message(_cleanError(error));
    }
  }

  Future<void> _showTransfer(Map<String, dynamic> row) async {
    try {
      final detail = await _service.detail(
        tenantId: _tenantId,
        transferId: row['id'].toString(),
      );
      if (!mounted) return;
      final transfer = Map<String, dynamic>.from(
        detail['transfer'] as Map? ?? const {},
      );
      final items = (detail['items'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      final history = (detail['history'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            '${transfer['transfer_number'] ?? 'Transfer'} • ${(transfer['status'] ?? '').toString().toUpperCase()}',
          ),
          content: SizedBox(
            width: 860,
            height: 560,
            child: ListView(
              children: [
                Text(
                  '${transfer['from_location']} → ${transfer['to_location']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Expected: ${transfer['expected_arrival_date'] ?? '—'} • Transport: ${transfer['transport_reference'] ?? '—'}',
                ),
                const Divider(height: 28),
                Text('Items', style: Theme.of(context).textTheme.titleMedium),
                ...items.map((raw) {
                  final item = Map<String, dynamic>.from(raw);
                  final allocations = (item['allocations'] as List? ?? const [])
                      .whereType<Map>()
                      .toList();
                  return Card(
                    child: ListTile(
                      title: Text('${item['product_name']} • ${item['sku']}'),
                      subtitle: Text(
                        'Requested ${item['quantity']} • Dispatched ${item['dispatched_quantity']} • Received ${item['received_quantity']} • ${(item['tracking_mode'] ?? 'none').toString().toUpperCase()}'
                        '${allocations.isEmpty ? '' : '\n${allocations.map((a) => a['serial_number'] ?? '${a['batch_number']} × ${a['quantity']}').join(', ')}'}',
                      ),
                    ),
                  );
                }),
                const Divider(height: 28),
                Text('History', style: Theme.of(context).textTheme.titleMedium),
                ...history.map((raw) {
                  final h = Map<String, dynamic>.from(raw);
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.history),
                    title: Text(
                      '${(h['event_type'] ?? '').toString().toUpperCase()} • ${h['from_status'] ?? '—'} → ${h['to_status'] ?? '—'}',
                    ),
                    subtitle: Text(
                      '${h['created_at'] ?? ''}${h['note'] == null ? '' : '\n${h['note']}'}',
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      _message(_cleanError(error));
    }
  }

  Future<void> _stockCount() async {
    final writable = _writableLocations;
    if (writable.isEmpty) {
      _message('You do not have manage access to a stock location.');
      return;
    }
    String locationId =
        _scopeLocationId ??
        widget.session.device?.locationId ??
        writable.first.id;
    if (!writable.any((e) => e.id == locationId)) {
      locationId = writable.first.id;
    }
    if (writable.length > 1) {
      final selected = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Count location'),
          children: writable
              .map(
                (l) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, l.id),
                  child: ListTile(
                    leading: Icon(
                      l.isWarehouse
                          ? Icons.warehouse_outlined
                          : Icons.store_outlined,
                    ),
                    title: Text('${l.code} • ${l.name}'),
                    subtitle: Text(l.roleLabel),
                  ),
                ),
              )
              .toList(),
        ),
      );
      if (selected == null) return;
      locationId = selected;
    }
    final snapshot = await _service.countSnapshot(
      tenantId: _tenantId,
      locationId: locationId,
    );
    if (!mounted) return;
    if (snapshot.isEmpty) {
      _message('No stock products are available to count at this location.');
      return;
    }
    final posted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _V485StockCountDialog(
        service: _service,
        tenantId: _tenantId,
        locationId: locationId,
        locationName:
            '${_location(locationId)?.code ?? ''} • ${_location(locationId)?.name ?? ''}',
        snapshot: snapshot,
      ),
    );
    if (posted == true) {
      _message('Physical stock count posted and reconciled.');
      await _refresh();
    }
  }

  Future<void> _showWarehouse(Map<String, dynamic> warehouse) async {
    try {
      final rows = await _service.warehouseInventory(
        tenantId: _tenantId,
        locationId: warehouse['location_id']?.toString(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            '${warehouse['location_code']} • ${warehouse['location_name']}',
          ),
          content: SizedBox(
            width: 900,
            height: 520,
            child: rows.isEmpty
                ? const Center(child: Text('No warehouse stock yet.'))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final row = rows[index];
                      return ListTile(
                        title: Text('${row['product_name']} • ${row['sku']}'),
                        subtitle: Text(
                          'On hand ${row['on_hand']} • Available ${row['available']} • Reserved ${row['reserved']} • Damaged ${row['damaged']}'
                          '\nIn transit in ${row['in_transit_in']} • out ${row['in_transit_out']} • ${(row['tracking_mode'] ?? 'none').toString().toUpperCase()}',
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      _message(_cleanError(error));
    }
  }

  Future<void> _showCount(Map<String, dynamic> row) async {
    try {
      final detail = await _service.countDetail(
        tenantId: _tenantId,
        countId: row['id'].toString(),
      );
      if (!mounted) return;
      final count = Map<String, dynamic>.from(
        detail['count'] as Map? ?? const {},
      );
      final items = (detail['items'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${count['count_number']} • ${count['location_name']}'),
          content: SizedBox(
            width: 860,
            height: 520,
            child: ListView(
              children: [
                Text(
                  'Posted: ${count['posted_at'] ?? '—'} • ${count['reconciliation_status'] ?? ''}',
                ),
                const SizedBox(height: 12),
                ...items.map((raw) {
                  final item = Map<String, dynamic>.from(raw);
                  return ListTile(
                    dense: true,
                    title: Text('${item['product_name']} • ${item['sku']}'),
                    subtitle: Text(
                      'System ${item['system_quantity']} • Counted ${item['counted_quantity']} • Variance ${item['variance']} • ${(item['tracking_mode'] ?? 'none').toString().toUpperCase()}',
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      _message(_cleanError(error));
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 4,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 25,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Warehouse & Transfers',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Transfer, warehouse, count and reconciliation',
                          style: TextStyle(
                            fontSize: 8.3,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_canCount)
                    OutlinedButton.icon(
                      onPressed: _stockCount,
                      icon: const Icon(Icons.fact_check_outlined, size: 15),
                      label: const Text('Stock Count'),
                    ),
                  if (_canManage) ...[
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      onPressed: _createTransfer,
                      icon: const Icon(Icons.swap_horiz, size: 15),
                      label: const Text('New Transfer'),
                    ),
                  ],
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: 'Refresh',
                    visualDensity: VisualDensity.compact,
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: const TabBar(
                isScrollable: true,
                labelStyle: TextStyle(
                  fontSize: 8.8,
                  fontWeight: FontWeight.w800,
                ),
                tabs: [
                  Tab(
                    icon: Icon(Icons.swap_horiz, size: 15),
                    text: 'Transfers',
                  ),
                  Tab(
                    icon: Icon(Icons.warehouse_outlined, size: 15),
                    text: 'Warehouses',
                  ),
                  Tab(
                    icon: Icon(Icons.fact_check_outlined, size: 15),
                    text: 'Stock Counts',
                  ),
                  Tab(
                    icon: Icon(Icons.balance_outlined, size: 15),
                    text: 'Reconciliation',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: TabBarView(
                children: [
                  _transferList(),
                  _warehouseList(),
                  _countList(),
                  _reconciliationList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transferList() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _transfers,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(child: Text(snapshot.error.toString()));
      }
      final rows = snapshot.data ?? const [];
      if (rows.isEmpty) {
        return const Center(child: Text('No stock transfers yet.'));
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final row = rows[index];
            final status = row['status']?.toString() ?? '';
            return Card(
              child: ListTile(
                onTap: () => _showTransfer(row),
                leading: CircleAvatar(
                  child: Icon(
                    status == 'in_transit'
                        ? Icons.local_shipping_outlined
                        : status == 'received'
                        ? Icons.inventory_2_outlined
                        : Icons.swap_horiz,
                  ),
                ),
                title: Text(
                  '${row['transfer_number']} • ${row['from_location']} → ${row['to_location']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${row['item_count']} item(s) • Qty ${row['total_quantity']}'
                  '${status == 'in_transit' ? ' • In transit ${row['in_transit_quantity']}' : ''}'
                  '${_number(row['serial_count']) > 0 ? ' • ${row['serial_count']} serial(s)' : ''}'
                  '${_number(row['batch_quantity']) > 0 ? ' • batch qty ${row['batch_quantity']}' : ''}'
                  '\n${row['created_at'] ?? ''}${row['expected_arrival_date'] == null ? '' : ' • ETA ${row['expected_arrival_date']}'}',
                ),
                isThreeLine: true,
                trailing: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(label: Text(status.toUpperCase())),
                    if (_canApprove && status == 'requested')
                      OutlinedButton(
                        onPressed: () => _action(row, 'approve'),
                        child: const Text('Approve'),
                      ),
                    if (_canApprove && status == 'requested')
                      TextButton(
                        onPressed: () => _action(row, 'reject'),
                        child: const Text('Reject'),
                      ),
                    if (_canManage && status == 'approved')
                      FilledButton.tonal(
                        onPressed: () => _action(row, 'dispatch'),
                        child: const Text('Dispatch'),
                      ),
                    if (_canManage &&
                        (status == 'requested' || status == 'approved'))
                      TextButton(
                        onPressed: () => _action(row, 'cancel'),
                        child: const Text('Cancel'),
                      ),
                    if (_canManage && status == 'in_transit')
                      FilledButton(
                        onPressed: () => _action(row, 'receive'),
                        child: const Text('Receive'),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );

  Widget _warehouseList() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _warehouses,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(child: Text(snapshot.error.toString()));
      }
      final rows = snapshot.data ?? const [];
      if (rows.isEmpty) {
        return const Center(
          child: Text(
            'No warehouse locations yet. Create a business location with type/role Warehouse.',
          ),
        );
      }
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 430,
          mainAxisExtent: 210,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: rows.length,
        itemBuilder: (_, index) {
          final row = rows[index];
          return Card(
            child: InkWell(
              onTap: () => _showWarehouse(row),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warehouse_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${row['location_code']} • ${row['location_name']}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Products ${row['product_count']} • On hand ${row['on_hand']}',
                    ),
                    Text(
                      'Available ${row['available']} • Reserved ${row['reserved']}',
                    ),
                    Text(
                      'Damaged ${row['damaged']} • Quarantine ${row['quarantine']}',
                    ),
                    const Spacer(),
                    Text(
                      'In transit: ${row['in_transit_in']} incoming • ${row['in_transit_out']} outgoing',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  Widget _countList() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _counts,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(child: Text(snapshot.error.toString()));
      }
      final rows = snapshot.data ?? const [];
      if (rows.isEmpty) {
        return const Center(
          child: Text('No physical stock counts posted yet.'),
        );
      }
      return ListView.separated(
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final row = rows[index];
          final variance = _number(row['total_variance']);
          return ListTile(
            onTap: () => _showCount(row),
            leading: CircleAvatar(
              child: Icon(
                variance.abs() > .000001
                    ? Icons.rule_folder_outlined
                    : Icons.fact_check_outlined,
              ),
            ),
            title: Text(
              '${row['count_number']} • ${row['location_name']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${row['line_count']} lines • System ${row['total_system_quantity']} • Counted ${row['total_counted_quantity']} • Variance ${row['total_variance']}\n${row['posted_at'] ?? row['created_at'] ?? ''}',
            ),
            isThreeLine: true,
            trailing: Chip(
              label: Text(
                (row['reconciliation_status'] ?? '').toString().toUpperCase(),
              ),
            ),
          );
        },
      );
    },
  );

  Widget _reconciliationList() => Column(
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: FilterChip(
          selected: _onlyVariance,
          label: const Text('Only mismatches / variance'),
          onSelected: (value) {
            setState(() {
              _onlyVariance = value;
              _reconciliation = _service.reconciliation(
                tenantId: _tenantId,
                locationId: _scopeLocationId,
                onlyVariance: value,
              );
            });
          },
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _reconciliation,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text(snapshot.error.toString()));
            }
            final rows = snapshot.data ?? const [];
            if (rows.isEmpty) {
              return const Center(
                child: Text('No reconciliation issues found.'),
              );
            }
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final row = rows[index];
                final status = row['reconciliation_status']?.toString() ?? 'OK';
                final good = status == 'OK';
                return ListTile(
                  leading: Icon(
                    good
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                  ),
                  title: Text('${row['product_name']} • ${row['sku']}'),
                  subtitle: Text(
                    '${row['location_name']} • ${(row['tracking_mode'] ?? 'none').toString().toUpperCase()}'
                    '\nLocation ${row['location_quantity']} • Tracked ${row['tracked_quantity']} • Reserved ${row['reserved_quantity']} • Available ${row['available_quantity']}'
                    '\nCompany ${row['company_stock_quantity']} • Sum of locations ${row['all_locations_quantity']}'
                    '${row['latest_count_number'] == null ? '' : ' • Last count ${row['latest_count_number']} variance ${row['latest_count_variance']}'}',
                  ),
                  isThreeLine: true,
                  trailing: Chip(label: Text(status)),
                );
              },
            );
          },
        ),
      ),
    ],
  );
}

class _V485StockCountDialog extends StatefulWidget {
  final StockTransferService service;
  final String tenantId;
  final String locationId;
  final String locationName;
  final List<Map<String, dynamic>> snapshot;

  const _V485StockCountDialog({
    required this.service,
    required this.tenantId,
    required this.locationId,
    required this.locationName,
    required this.snapshot,
  });

  @override
  State<_V485StockCountDialog> createState() => _V485StockCountDialogState();
}

class _V485StockCountDialogState extends State<_V485StockCountDialog> {
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _search = TextEditingController();
  late final Map<String, TextEditingController> _editors;
  bool _saving = false;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _editors = {};
    for (final row in widget.snapshot) {
      final id = row['variant_id'].toString();
      final mode = row['tracking_mode']?.toString() ?? 'none';
      if (mode == 'serial') {
        final tracking = Map<String, dynamic>.from(
          row['tracking'] as Map? ?? const {},
        );
        final serials = (tracking['serial_numbers'] as List? ?? const [])
            .whereType<Map>()
            .map((s) => s['serial_number']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .join('\n');
        _editors[id] = TextEditingController(text: serials);
      } else if (mode == 'batch') {
        final tracking = Map<String, dynamic>.from(
          row['tracking'] as Map? ?? const {},
        );
        final batches = (tracking['batches'] as List? ?? const [])
            .whereType<Map>()
            .map((b) {
              final exp = b['expiry_on']?.toString() ?? '';
              return '${b['batch_number']}=${b['quantity']}|${b['damaged_quantity'] ?? 0}|$exp';
            })
            .join('\n');
        _editors[id] = TextEditingController(text: batches);
      } else {
        _editors[id] = TextEditingController(
          text: _number(
            row['system_quantity'],
          ).toStringAsFixed(_number(row['system_quantity']) % 1 == 0 ? 0 : 2),
        );
      }
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    _search.dispose();
    for (final c in _editors.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.snapshot;
    return widget.snapshot
        .where(
          (row) =>
              '${row['product_name']} ${row['sku']}'.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _editTracked(Map<String, dynamic> row) async {
    final mode = row['tracking_mode']?.toString() ?? 'none';
    final controller = _editors[row['variant_id'].toString()]!;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${row['product_name']} • ${mode.toUpperCase()} count'),
        content: SizedBox(
          width: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mode == 'serial'
                    ? 'Enter every physical serial found at this location, one per line. Missing registered serials will be marked missing; unknown serials will be registered.'
                    : 'Enter every physical batch as BATCH=SALEABLE|DAMAGED|EXPIRY. Example: LOT-01=8|2|2027-12-31. Omitted existing batches are reconciled to zero.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 10,
                maxLines: 18,
                decoration: InputDecoration(
                  labelText: mode == 'serial'
                      ? 'Physical serial numbers'
                      : 'Physical batch quantities',
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  (List<Map<String, dynamic>>?, String) _parseBatches(String text) {
    final rows = <Map<String, dynamic>>[];
    for (final line in _lines(text)) {
      final halves = line.split('=');
      if (halves.length != 2 || halves.first.trim().isEmpty) {
        return (null, 'Batch lines must use BATCH=SALEABLE|DAMAGED|EXPIRY.');
      }
      final parts = halves[1].split('|');
      final qty = double.tryParse(parts[0].trim()) ?? -1;
      final damaged = parts.length > 1 && parts[1].trim().isNotEmpty
          ? double.tryParse(parts[1].trim()) ?? -1
          : 0;
      if (qty < 0 || damaged < 0) {
        return (null, 'Batch quantities cannot be negative.');
      }
      final row = <String, dynamic>{
        'batch_number': halves[0].trim(),
        'quantity': qty,
        'damaged_quantity': damaged,
      };
      if (parts.length > 2 && parts[2].trim().isNotEmpty) {
        row['expiry_on'] = parts[2].trim();
      }
      rows.add(row);
    }
    return (rows, '');
  }

  Future<void> _post() async {
    final items = <Map<String, dynamic>>[];
    for (final row in widget.snapshot) {
      if (row['count_blocked'] == true) {
        setState(
          () => _error =
              '${row['product_name']} has reserved transfer stock. Dispatch/cancel it before counting.',
        );
        return;
      }
      final id = row['variant_id'].toString();
      final mode = row['tracking_mode']?.toString() ?? 'none';
      final text = _editors[id]!.text;
      if (mode == 'serial') {
        items.add({'variant_id': id, 'serial_numbers': _lines(text)});
      } else if (mode == 'batch') {
        final parsed = _parseBatches(text);
        if (parsed.$1 == null) {
          setState(() => _error = '${row['product_name']}: ${parsed.$2}');
          return;
        }
        items.add({'variant_id': id, 'batches': parsed.$1});
      } else {
        final value = double.tryParse(text.trim());
        if (value == null || value < 0) {
          setState(
            () => _error =
                '${row['product_name']}: counted quantity must be zero or more.',
          );
          return;
        }
        items.add({'variant_id': id, 'counted_quantity': value});
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.postCount(
        tenantId: widget.tenantId,
        locationId: widget.locationId,
        items: items,
        notes: _notes.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            icon: const Icon(Icons.close),
          ),
          title: Text('Physical Stock Count • ${widget.locationName}'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _saving ? null : _post,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(_saving ? 'Posting…' : 'Post & Reconcile'),
              ),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        labelText: 'Find product / SKU',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _notes,
                      decoration: const InputDecoration(
                        labelText: 'Count / reconciliation note',
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final row = rows[index];
                    final mode = row['tracking_mode']?.toString() ?? 'none';
                    final id = row['variant_id'].toString();
                    return ListTile(
                      title: Text('${row['product_name']} • ${row['sku']}'),
                      subtitle: Text(
                        'System ${row['system_quantity']} • Reserved ${row['reserved_quantity']} • Damaged ${row['damaged_quantity']} • ${mode.toUpperCase()}'
                        '${row['count_blocked'] == true ? ' • COUNT BLOCKED BY RESERVATION' : ''}',
                      ),
                      trailing: mode == 'none'
                          ? SizedBox(
                              width: 150,
                              child: TextField(
                                controller: _editors[id],
                                textAlign: TextAlign.right,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Counted',
                                  isDense: true,
                                ),
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: () => _editTracked(row),
                              icon: Icon(
                                mode == 'serial'
                                    ? Icons.numbers
                                    : Icons.inventory_2_outlined,
                              ),
                              label: Text(
                                mode == 'serial'
                                    ? '${_lines(_editors[id]!.text).length} serials'
                                    : 'Edit batches',
                              ),
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  const _ReadOnlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(labelText: label),
    child: Text(value),
  );
}

double _number(dynamic value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

List<String> _lines(String value) => value
    .split(RegExp(r'[\r\n,]+'))
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _cleanError(Object error) {
  final text = error.toString();
  return text
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('Exception: ', '');
}
