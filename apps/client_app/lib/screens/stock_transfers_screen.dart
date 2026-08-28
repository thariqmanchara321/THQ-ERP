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
  late Future<List<Map<String, dynamic>>> _future;

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('inventory.transfer') ||
      widget.session.hasPermission('inventory.manage');

  bool get _canApprove =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('inventory.manage') ||
      widget.session.hasPermission('approvals.approve');

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = _service.list(tenantId: widget.session.business.id);

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  Future<void> _create() async {
    final writable = LocationScopeService.writableLocations(widget.session);
    if (writable.isEmpty) {
      _message('You do not have operate access to any store.');
      return;
    }
    var fromId = LocationScopeService.selectedLocationId.value;
    if (fromId == null || !writable.any((location) => location.id == fromId)) {
      fromId = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Select source store'),
          children: writable
              .map(
                (location) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, location.id),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      location.isWarehouse
                          ? Icons.warehouse_outlined
                          : Icons.store_outlined,
                    ),
                    title: Text('${location.code} • ${location.name}'),
                    subtitle: Text(location.roleLabel),
                  ),
                ),
              )
              .toList(),
        ),
      );
      if (fromId == null) return;
    }
    final destinations = widget.session.locations
        .where((e) => e.id != fromId)
        .toList();
    if (destinations.isEmpty) {
      _message('Create another store/warehouse before making a transfer.');
      return;
    }
    final sourceId = fromId;
    final products = await InventoryService().getProducts(
      tenantId: widget.session.business.id,
      locationId: sourceId,
    );
    if (!mounted) return;
    if (products.isEmpty) {
      _message('No products are assigned to the source store.');
      return;
    }

    String toId = destinations.first.id;
    InventoryProduct product = products.first;
    final qty = TextEditingController(text: '1');
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Stock Transfer'),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ReadOnlyField(
                  label: 'From store',
                  value: widget.session.locations
                      .firstWhere((e) => e.id == sourceId)
                      .name,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: toId,
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
                            '${p.productName} • ${p.sku} • Stock ${p.stockQuantity.toStringAsFixed(2)}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(
                    () => product = products.firstWhere(
                      (p) => p.variantId == value,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qty,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Create Transfer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amount = double.tryParse(qty.text.trim()) ?? 0;
    if (amount <= 0) {
      _message('Enter a valid quantity.');
      return;
    }
    try {
      final result = await _service.create(
        tenantId: widget.session.business.id,
        fromLocationId: sourceId,
        toLocationId: toId,
        items: [
          {'variant_id': product.variantId, 'quantity': amount},
        ],
        notes: notes.text,
      );
      _message('Transfer ${result['transfer_number']} created.');
      _refresh();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _stockCount() async {
    final locationId = LocationScopeService.currentForCreate(widget.session);
    final products = await InventoryService().getProducts(
      tenantId: widget.session.business.id,
      locationId: locationId,
    );
    if (!mounted) return;
    if (products.isEmpty) {
      _message('No products are assigned to this store.');
      return;
    }
    final posted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StockCountDialog(
        session: widget.session,
        locationId: locationId,
        products: products,
      ),
    );
    if (posted == true) {
      _message('Physical stock count posted successfully.');
    }
  }

  Future<String?> _reasonDialog(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Reason / note'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _action(Map<String, dynamic> row, String action) async {
    try {
      final transferId = row['id'].toString();
      if (action == 'approve') {
        await _service.approve(
          tenantId: widget.session.business.id,
          transferId: transferId,
        );
      } else if (action == 'reject') {
        final reason = await _reasonDialog('Reject Stock Transfer');
        if (reason == null) return;
        await _service.reject(
          tenantId: widget.session.business.id,
          transferId: transferId,
          reason: reason,
        );
      } else if (action == 'cancel') {
        final reason = await _reasonDialog('Cancel Stock Transfer');
        if (reason == null) return;
        await _service.cancel(
          tenantId: widget.session.business.id,
          transferId: transferId,
          reason: reason,
        );
      } else if (action == 'dispatch') {
        await _service.dispatch(
          tenantId: widget.session.business.id,
          transferId: transferId,
        );
      } else if (action == 'receive') {
        await _service.receive(
          tenantId: widget.session.business.id,
          transferId: transferId,
        );
      }
      final labels = <String, String>{
        'approve': 'Transfer approved.',
        'reject': 'Transfer rejected and reserved stock released.',
        'cancel': 'Transfer cancelled and reserved stock released.',
        'dispatch': 'Transfer dispatched and is now in transit.',
        'receive': 'Transfer received into destination stock.',
      };
      _message(labels[action] ?? 'Transfer updated.');
      _refresh();
    } catch (error) {
      _message(error.toString());
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const SizedBox(
                width: 480,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stock Transfers',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Move physical stock safely between stores and warehouses.',
                    ),
                  ],
                ),
              ),
              if (_canManage)
                FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('New Transfer'),
                ),
              if (_canManage &&
                  (widget.session.hasRole('owner') ||
                      widget.session.hasPermission('inventory.stock_count') ||
                      widget.session.hasPermission('inventory.manage')))
                OutlinedButton.icon(
                  onPressed: _stockCount,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Physical Stock Count'),
                ),
              IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
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
                          leading: const CircleAvatar(
                            child: Icon(Icons.swap_horiz),
                          ),
                          title: Text(
                            '${row['transfer_number']}  •  ${row['from_location']} → ${row['to_location']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${row['item_count']} item(s) • Qty ${row['total_quantity']}'
                            '${status == 'dispatched' ? ' • In transit ${row['in_transit_quantity'] ?? 0}' : ''}'
                            ' • ${row['created_at'] ?? ''}',
                          ),
                          trailing: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Chip(label: Text(status.toUpperCase())),
                              if (_canApprove && status == 'requested')
                                OutlinedButton(
                                  onPressed: () => _action(row, 'approve'),
                                  child: const Text('Approve'),
                                ),
                              if (_canApprove &&
                                  (status == 'requested' ||
                                      status == 'approved'))
                                TextButton(
                                  onPressed: () => _action(row, 'reject'),
                                  child: const Text('Reject'),
                                ),
                              if (_canManage && status == 'approved')
                                OutlinedButton(
                                  onPressed: () => _action(row, 'dispatch'),
                                  child: const Text('Dispatch'),
                                ),
                              if (_canManage &&
                                  (status == 'requested' ||
                                      status == 'approved'))
                                TextButton(
                                  onPressed: () => _action(row, 'cancel'),
                                  child: const Text('Cancel'),
                                ),
                              if (_canManage && status == 'dispatched')
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
            ),
          ),
        ],
      ),
    );
  }
}

class _StockCountDialog extends StatefulWidget {
  final ClientSession session;
  final String locationId;
  final List<InventoryProduct> products;

  const _StockCountDialog({
    required this.session,
    required this.locationId,
    required this.products,
  });

  @override
  State<_StockCountDialog> createState() => _StockCountDialogState();
}

class _StockCountDialogState extends State<_StockCountDialog> {
  final InventoryService _inventory = InventoryService();
  final TextEditingController _search = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  late final Map<String, TextEditingController> _counts;
  bool _saving = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _counts = {
      for (final product in widget.products)
        product.variantId: TextEditingController(
          text: product.stockQuantity.toStringAsFixed(
            product.stockQuantity % 1 == 0 ? 0 : 2,
          ),
        ),
    };
  }

  @override
  void dispose() {
    _search.dispose();
    _notes.dispose();
    for (final controller in _counts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<InventoryProduct> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.products;
    return widget.products
        .where(
          (p) =>
              p.productName.toLowerCase().contains(q) ||
              p.sku.toLowerCase().contains(q) ||
              (p.barcode ?? '').toLowerCase().contains(q) ||
              (p.partNumber ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _post() async {
    final rows = <Map<String, dynamic>>[];
    for (final product in widget.products) {
      final value = double.tryParse(_counts[product.variantId]!.text.trim());
      if (value == null || value < 0) {
        setState(() => _error = 'Every counted quantity must be zero or more.');
        return;
      }
      rows.add({'variant_id': product.variantId, 'counted_quantity': value});
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _inventory.postStockCount(
        tenantId: widget.session.business.id,
        locationId: widget.locationId,
        items: rows,
        notes: _notes.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _filtered;
    final location = widget.session.locations
        .where((e) => e.id == widget.locationId)
        .firstOrNull;
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            icon: const Icon(Icons.close),
          ),
          title: Text('Physical Stock Count • ${location?.code ?? 'Store'}'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _saving ? null : _post,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(_saving ? 'Posting…' : 'Post Count'),
              ),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 420,
                    child: TextField(
                      controller: _search,
                      autofocus: true,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        labelText: 'Find product / SKU / barcode / part number',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 420,
                    child: TextField(
                      controller: _notes,
                      decoration: const InputDecoration(
                        labelText: 'Count note / reason',
                        prefixIcon: Icon(Icons.notes_outlined),
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
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      title: Text(product.productName),
                      subtitle: Text(
                        '${product.sku} • System ${product.stockQuantity.toStringAsFixed(2)}',
                      ),
                      trailing: SizedBox(
                        width: 150,
                        child: TextField(
                          controller: _counts[product.variantId],
                          textAlign: TextAlign.right,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Counted',
                            isDense: true,
                          ),
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
