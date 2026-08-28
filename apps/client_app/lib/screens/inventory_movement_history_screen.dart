import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/client_session.dart';
import '../services/inventory_service.dart';
import '../services/location_scope_service.dart';

class InventoryMovementHistoryScreen extends StatefulWidget {
  final ClientSession session;

  const InventoryMovementHistoryScreen({super.key, required this.session});

  @override
  State<InventoryMovementHistoryScreen> createState() => _InventoryMovementHistoryScreenState();
}

class _InventoryMovementHistoryScreenState extends State<InventoryMovementHistoryScreen> {
  final InventoryService _service = InventoryService();
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  String _type = 'all';
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  final DateTime _to = DateTime.now().add(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.movementHistory(
        tenantId: widget.session.business.id,
        locationId: LocationScopeService.currentForRead(widget.session),
        movementType: _type == 'all' ? null : _type,
        from: _from,
        to: _to,
        limit: 2000,
      );
      if (mounted) setState(() => _rows = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickFrom() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (value == null) return;
    setState(() => _from = value);
    await _load();
  }

  double _n(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  String _q(dynamic value) {
    final n = _n(value).abs();
    return n.toStringAsFixed(n % 1 == 0 ? 0 : 3);
  }

  @override
  Widget build(BuildContext context) {
    final incoming = _rows.where((r) => _n(r['base_quantity_delta']) > 0).fold<double>(0, (a, r) => a + _n(r['base_quantity_delta']));
    final outgoing = _rows.where((r) => _n(r['base_quantity_delta']) < 0).fold<double>(0, (a, r) => a + _n(r['base_quantity_delta']).abs());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Movement Ledger'),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(onPressed: _pickFrom, icon: const Icon(Icons.date_range), label: Text('From ${DateFormat('dd MMM yyyy').format(_from)}')),
                DropdownButton<String>(
                  value: _type,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All movements')),
                    DropdownMenuItem(value: 'purchase', child: Text('Purchase')),
                    DropdownMenuItem(value: 'sale', child: Text('Sale')),
                    DropdownMenuItem(value: 'sale_return', child: Text('Sales Return')),
                    DropdownMenuItem(value: 'purchase_return', child: Text('Purchase Return')),
                    DropdownMenuItem(value: 'transfer_in', child: Text('Transfer In')),
                    DropdownMenuItem(value: 'transfer_out', child: Text('Transfer Out')),
                    DropdownMenuItem(value: 'stock_count', child: Text('Stock Count')),
                    DropdownMenuItem(value: 'adjustment_in', child: Text('Adjustment In')),
                    DropdownMenuItem(value: 'adjustment_out', child: Text('Adjustment Out')),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => _type = value);
                    await _load();
                  },
                ),
                Chip(label: Text('${_rows.length} movements')),
                Chip(label: Text('In ${_q(incoming)} base units')),
                Chip(label: Text('Out ${_q(outgoing)} base units')),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 8),
            Expanded(
              child: _rows.isEmpty && !_loading
                  ? const Center(child: Text('No inventory movements in this period.'))
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        final delta = _n(row['base_quantity_delta']);
                        final display = _n(row['display_quantity']);
                        final before = row['balance_before'];
                        final after = row['balance_after'];
                        final unit = row['unit_code']?.toString() ?? '';
                        final time = DateTime.tryParse(row['occurred_at']?.toString() ?? '');
                        return ListTile(
                          leading: CircleAvatar(
                            child: Icon(delta >= 0 ? Icons.south_west : Icons.north_east, size: 18),
                          ),
                          title: Text('${row['product_name'] ?? 'Product'} • ${row['movement_type'] ?? ''}'),
                          subtitle: Text([
                            row['location_name']?.toString(),
                            row['reference_number']?.toString(),
                            if (before != null && after != null) 'Balance ${_q(before)} → ${_q(after)}',
                            if (time != null) DateFormat('dd MMM yyyy • hh:mm a').format(time.toLocal()),
                          ].whereType<String>().where((x) => x.isNotEmpty).join(' • ')),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${display >= 0 ? '+' : '-'}${_q(display)} $unit', style: const TextStyle(fontWeight: FontWeight.w800)),
                              if ((display.abs() - delta.abs()).abs() > .000001) Text('Base ${delta >= 0 ? '+' : '-'}${_q(delta)}', style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
