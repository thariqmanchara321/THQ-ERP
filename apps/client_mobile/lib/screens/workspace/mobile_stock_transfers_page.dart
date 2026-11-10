import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/mobile_session.dart';
import '../../services/mobile_client_service.dart';
import '../../widgets/mobile_workspace_widgets.dart';

class MobileStockTransfersPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileStockTransfersPage({
    super.key,
    required this.session,
    required this.service,
    this.locationId,
  });

  @override
  State<MobileStockTransfersPage> createState() =>
      _MobileStockTransfersPageState();
}

class _MobileStockTransfersPageState extends State<MobileStockTransfersPage> {
  final _searchCtrl = TextEditingController();
  late Future<List<Map<String, dynamic>>> _transfersFuture;
  String _selectedStatus = 'all';

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
    _transfersFuture = widget.service.stockTransfers(
      widget.session,
      locationId: widget.locationId,
      status: _selectedStatus == 'all' ? null : _selectedStatus,
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    await _transfersFuture;
  }

  void _createTransfer() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _CreateStockTransferPage(
          session: widget.session,
          service: widget.service,
          currentLocationId: widget.locationId,
        ),
      ),
    );
    if (created == true && mounted) {
      _refresh();
    }
  }

  void _openDetail(Map<String, dynamic> transfer) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _StockTransferDetailPage(
          session: widget.session,
          service: widget.service,
          transferSummary: transfer,
        ),
      ),
    );
    if (updated == true && mounted) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Transfers'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createTransfer,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Transfer'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search transfer # or store...',
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
                _FilterChip(
                  label: 'All',
                  selected: _selectedStatus == 'all',
                  onSelected: () => setState(() {
                    _selectedStatus = 'all';
                    _load();
                  }),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Requested / Draft',
                  selected: _selectedStatus == 'requested',
                  onSelected: () => setState(() {
                    _selectedStatus = 'requested';
                    _load();
                  }),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Dispatched',
                  selected: _selectedStatus == 'dispatched',
                  onSelected: () => setState(() {
                    _selectedStatus = 'dispatched';
                    _load();
                  }),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Received',
                  selected: _selectedStatus == 'received',
                  onSelected: () => setState(() {
                    _selectedStatus = 'received';
                    _load();
                  }),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Cancelled',
                  selected: _selectedStatus == 'cancelled',
                  onSelected: () => setState(() {
                    _selectedStatus = 'cancelled';
                    _load();
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _transfersFuture,
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
                          Text('Failed to load transfers: ${snapshot.error}', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _refresh, child: const Text('Try Again')),
                        ],
                      ),
                    ),
                  );
                }

                final allRows = snapshot.data ?? [];
                final query = _searchCtrl.text.trim().toLowerCase();
                final filtered = allRows.where((row) {
                  if (query.isEmpty) return true;
                  final num = (row['transfer_number'] ?? '').toString().toLowerCase();
                  final from = (row['from_location_name'] ?? row['source_location_name'] ?? '').toString().toLowerCase();
                  final to = (row['to_location_name'] ?? row['destination_location_name'] ?? '').toString().toLowerCase();
                  final status = (row['status'] ?? '').toString().toLowerCase();
                  return num.contains(query) || from.contains(query) || to.contains(query) || status.contains(query);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_horiz_rounded, size: 48, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 10),
                        const Text('No stock transfers found', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          'Create a transfer to move goods between locations.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final item = filtered[i];
                      final number = item['transfer_number'] ?? 'TRF-${item['id']}';
                      final fromName = item['from_location_name'] ?? item['source_location_name'] ?? 'Store A';
                      final toName = item['to_location_name'] ?? item['destination_location_name'] ?? 'Store B';
                      final status = (item['status'] ?? 'draft').toString().toLowerCase();
                      final date = item['created_at']?.toString().split('T').first ?? '';

                      Color statusColor;
                      switch (status) {
                        case 'received':
                          statusColor = Colors.green;
                          break;
                        case 'dispatched':
                          statusColor = Colors.orange;
                          break;
                        case 'cancelled':
                          statusColor = Colors.red;
                          break;
                        default:
                          statusColor = Colors.blue;
                      }

                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: InkWell(
                          onTap: () => _openDetail(item),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '$number',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Icon(Icons.arrow_upward_rounded, size: 16, color: Colors.blue.shade700),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              '$fromName',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                          const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 6),
                                            child: Icon(Icons.arrow_forward_rounded, size: 14),
                                          ),
                                          Icon(Icons.arrow_downward_rounded, size: 16, color: Colors.green.shade700),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              '$toName',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (date.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Date: $date',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
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

class _CreateStockTransferPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? currentLocationId;

  const _CreateStockTransferPage({
    required this.session,
    required this.service,
    this.currentLocationId,
  });

  @override
  State<_CreateStockTransferPage> createState() =>
      _CreateStockTransferPageState();
}

class _CreateStockTransferPageState extends State<_CreateStockTransferPage> {
  String? _fromLocationId;
  String? _toLocationId;
  final _notesCtrl = TextEditingController();
  final _transportCtrl = TextEditingController();
  final List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  List<Map<String, dynamic>> _sourceInventory = [];

  @override
  void initState() {
    super.initState();
    _fromLocationId = widget.currentLocationId ?? widget.session.locationId;
    final other = widget.session.locations.where((l) => l.id != _fromLocationId).toList();
    if (other.isNotEmpty) {
      _toLocationId = other.first.id;
    }
    _loadSourceInventory();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _transportCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSourceInventory() async {
    if (_fromLocationId == null) return;
    try {
      final rows = await widget.service.warehouseInventory(
        widget.session,
        locationId: _fromLocationId,
      );
      if (mounted) setState(() => _sourceInventory = rows);
    } catch (_) {}
  }

  void _addItem() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _TransferItemPicker(inventory: _sourceInventory),
    );
    if (result != null && mounted) {
      setState(() => _items.add(result));
    }
  }

  Future<void> _submit() async {
    if (_fromLocationId == null || _toLocationId == null) {
      ThqNotify.error(context, 'Validation', message: 'Source and destination locations are required.');
      return;
    }
    if (_fromLocationId == _toLocationId) {
      ThqNotify.error(context, 'Validation', message: 'Source and destination locations must be different.');
      return;
    }
    if (_items.isEmpty) {
      ThqNotify.error(context, 'Validation', message: 'Please add at least one item to transfer.');
      return;
    }

    setState(() => _loading = true);
    try {
      final payloadItems = _items.map((i) => {
        'variant_id': i['variant_id'] ?? i['id'],
        'quantity': i['quantity'],
        'notes': i['notes'] ?? '',
      }).toList();

      final res = await widget.service.createStockTransfer(
        widget.session,
        fromLocationId: _fromLocationId!,
        toLocationId: _toLocationId!,
        items: payloadItems,
        notes: _notesCtrl.text.trim(),
        transportReference: _transportCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() => _loading = false);
      final trfNum = res['transfer_number'] ?? 'Created';
      ThqNotify.success(context, 'Transfer Created', message: 'Stock transfer $trfNum requested.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ThqNotify.error(context, 'Transfer Failed', message: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Stock Transfer')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Locations', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _fromLocationId,
                    decoration: InputDecoration(
                      labelText: 'Source Location (Dispatched From) *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: widget.session.locations
                        .map((l) => DropdownMenuItem(value: l.id, child: Text(l.name)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _fromLocationId = val;
                          _items.clear();
                          _loadSourceInventory();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _toLocationId,
                    decoration: InputDecoration(
                      labelText: 'Destination Location (Delivered To) *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: widget.session.locations
                        .map((l) => DropdownMenuItem(value: l.id, child: Text(l.name)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _toLocationId = val);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items to Transfer (${_items.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
              FilledButton.tonalIcon(
                onPressed: _addItem,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Item'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(child: Text('No items selected for transfer yet')),
            )
          else
            ..._items.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: ListTile(
                  title: Text(item['name'] ?? 'Item', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Qty: ${item['quantity']} ${item['unit_code'] ?? 'pcs'}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                    onPressed: () => setState(() => _items.removeAt(idx)),
                  ),
                ),
              );
            }),
          const SizedBox(height: 14),
          TextField(
            controller: _transportCtrl,
            decoration: InputDecoration(
              labelText: 'Transport / Vehicle Reference',
              hintText: 'e.g. Truck KL-07-AB-1234',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            decoration: InputDecoration(
              labelText: 'Transfer Notes',
              hintText: 'Reason or shipment details...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
      bottomSheet: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -3)),
            ],
          ),
          child: FilledButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded),
            label: Text(_loading ? 'Requesting Transfer...' : 'Request Stock Transfer'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ),
    );
  }
}

class _TransferItemPicker extends StatefulWidget {
  final List<Map<String, dynamic>> inventory;

  const _TransferItemPicker({required this.inventory});

  @override
  State<_TransferItemPicker> createState() => _TransferItemPickerState();
}

class _TransferItemPickerState extends State<_TransferItemPicker> {
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  Map<String, dynamic>? _selected;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = widget.inventory.where((row) {
      if (q.isEmpty) return true;
      final name = (row['product_name'] ?? row['name'] ?? '').toString().toLowerCase();
      final sku = (row['sku'] ?? '').toString().toLowerCase();
      return name.contains(q) || sku.contains(q);
    }).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Select Item to Transfer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (_selected == null) ...[
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search product in source store...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length.clamp(0, 50),
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = filtered[i];
                    final name = (item['product_name'] ?? item['name'] ?? 'Product').toString();
                    final qty = item['quantity'] ?? item['available_quantity'] ?? 0;
                    final unit = item['unit_code'] ?? 'pcs';
                    return ListTile(
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Available: $qty $unit'),
                      onTap: () => setState(() => _selected = item),
                    );
                  },
                ),
              ),
            ] else ...[
              ListTile(
                title: Text((_selected!['product_name'] ?? _selected!['name']).toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Available: ${_selected!['quantity'] ?? 0} ${_selected!['unit_code'] ?? 'pcs'}'),
                trailing: TextButton(
                  onPressed: () => setState(() => _selected = null),
                  child: const Text('Change'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Transfer Quantity *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0;
                  if (qty <= 0) {
                    ThqNotify.error(context, 'Validation', message: 'Quantity must be positive.');
                    return;
                  }
                  Navigator.pop(context, {
                    'variant_id': _selected!['variant_id'] ?? _selected!['id'],
                    'name': _selected!['product_name'] ?? _selected!['name'],
                    'unit_code': _selected!['unit_code'] ?? 'pcs',
                    'quantity': qty,
                  });
                },
                child: const Text('Confirm Item'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StockTransferDetailPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final Map<String, dynamic> transferSummary;

  const _StockTransferDetailPage({
    required this.session,
    required this.service,
    required this.transferSummary,
  });

  @override
  State<_StockTransferDetailPage> createState() =>
      _StockTransferDetailPageState();
}

class _StockTransferDetailPageState extends State<_StockTransferDetailPage> {
  late Future<Map<String, dynamic>> _detailFuture;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final trfId = widget.transferSummary['id']?.toString() ?? '';
    _detailFuture = widget.service.stockTransferDetail(widget.session, trfId);
  }

  Future<void> _receiveTransfer(String transferId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Receive Stock Transfer'),
        content: const Text('Confirm that all items have arrived at your destination location? This will add goods into destination stock.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm Receipt')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _acting = true);
    try {
      await widget.service.receiveStockTransfer(widget.session, transferId: transferId);
      if (!mounted) return;
      setState(() => _acting = false);
      ThqNotify.success(context, 'Received', message: 'Stock received and updated in inventory.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _acting = false);
      ThqNotify.error(context, 'Receipt Failed', message: '$e');
    }
  }

  Future<void> _dispatchTransfer(String transferId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dispatch Stock Transfer'),
        content: const Text('Mark this transfer as dispatched and in transit?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dispatch')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _acting = true);
    try {
      await widget.service.dispatchStockTransfer(widget.session, transferId: transferId);
      if (!mounted) return;
      setState(() => _acting = false);
      ThqNotify.success(context, 'Dispatched', message: 'Transfer dispatched successfully.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _acting = false);
      ThqNotify.error(context, 'Dispatch Failed', message: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final num = widget.transferSummary['transfer_number'] ?? 'Transfer Details';

    return Scaffold(
      appBar: AppBar(title: Text('$num')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final detail = snapshot.data ?? widget.transferSummary;
          final transferId = (detail['id'] ?? widget.transferSummary['id']).toString();
          final status = (detail['status'] ?? widget.transferSummary['status'] ?? '').toString().toLowerCase();
          final items = (detail['items'] as List? ?? const []).whereType<Map>().toList();

          final canDispatch = status == 'requested' || status == 'draft' || status == 'approved';
          final canReceive = status == 'dispatched' || status == 'in_transit';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Status: ${status.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(detail['created_at']?.toString().split('T').first ?? ''),
                        ],
                      ),
                      const Divider(height: 16),
                      Text('From: ${detail['from_location_name'] ?? 'Source store'}'),
                      const SizedBox(height: 4),
                      Text('To: ${detail['to_location_name'] ?? 'Destination store'}'),
                      if (detail['transport_reference'] != null && detail['transport_reference'].toString().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Vehicle: ${detail['transport_reference']}'),
                      ],
                      if (detail['notes'] != null && detail['notes'].toString().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Notes: ${detail['notes']}'),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Items (${items.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Center(child: Text('No item lines available'))
              else
                ...items.map((it) => Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text(it['product_name'] ?? it['item_name'] ?? 'Item', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('Qty: ${it['quantity'] ?? it['requested_quantity']} ${it['unit_code'] ?? 'pcs'}'),
                        trailing: it['received_quantity'] != null
                            ? Text('Recv: ${it['received_quantity']}', style: const TextStyle(fontSize: 12, color: Colors.green))
                            : null,
                      ),
                    )),
              const SizedBox(height: 24),
              if (canDispatch) ...[
                FilledButton.icon(
                  onPressed: _acting ? null : () => _dispatchTransfer(transferId),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Dispatch Stock Transfer'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
                const SizedBox(height: 8),
              ],
              if (canReceive) ...[
                FilledButton.icon(
                  onPressed: _acting ? null : () => _receiveTransfer(transferId),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Receive Stock at Destination'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: Colors.green.shade700,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
