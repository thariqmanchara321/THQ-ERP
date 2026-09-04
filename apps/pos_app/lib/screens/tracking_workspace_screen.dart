import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/tracking_service.dart';

class TrackingWorkspaceScreen extends StatefulWidget {
  final ClientSession session;
  const TrackingWorkspaceScreen({super.key, required this.session});

  @override
  State<TrackingWorkspaceScreen> createState() =>
      _TrackingWorkspaceScreenState();
}

class _TrackingWorkspaceScreenState extends State<TrackingWorkspaceScreen> {
  final TrackingService _service = TrackingService();
  final TextEditingController _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _serials = const [];
  List<Map<String, dynamic>> _batches = const [];
  List<Map<String, dynamic>> _warranties = const [];

  String get _tenantId => widget.session.business.id;

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
      final q = _search.text.trim();
      await _service.syncWarranties(tenantId: _tenantId);
      final result = await Future.wait([
        _service.searchSerials(tenantId: _tenantId, query: q),
        _service.searchBatches(tenantId: _tenantId, query: q),
        _service.warranties(tenantId: _tenantId, query: q),
      ]);
      if (!mounted) return;
      setState(() {
        _serials = result[0];
        _batches = result[1];
        _warranties = result[2];
      });
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');
  String _value(dynamic value) =>
      value == null || value.toString().isEmpty ? '-' : value.toString();

  Future<void> _showSerial(Map<String, dynamic> row) async {
    try {
      final detail = await _service.serialHistory(
        tenantId: _tenantId,
        serialId: row['serial_id'].toString(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _HistoryDialog(
          title: 'Serial ${row['serial_number']}',
          detail: detail,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_clean(e))));
      }
    }
  }

  Future<void> _showBatch(Map<String, dynamic> row) async {
    try {
      final detail = await _service.batchHistory(
        tenantId: _tenantId,
        batchId: row['batch_id'].toString(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _HistoryDialog(
          title: 'Batch ${row['batch_number']}',
          detail: detail,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_clean(e))));
      }
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 3,
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
                  const Expanded(
                    child: Text(
                      'Serial / Batch / Warranty',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    visualDensity: VisualDensity.compact,
                    onPressed: _loading ? null : _load,
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
                labelStyle: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
                tabs: [
                  Tab(
                    icon: Icon(Icons.numbers_outlined, size: 15),
                    text: 'Serials',
                  ),
                  Tab(
                    icon: Icon(Icons.inventory_2_outlined, size: 15),
                    text: 'Batches',
                  ),
                  Tab(
                    icon: Icon(Icons.verified_user_outlined, size: 15),
                    text: 'Warranty',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Container(
              height: 40,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onSubmitted: (_) => _load(),
                      decoration: const InputDecoration(
                        hintText:
                            'Serial, batch, product, SKU, supplier, customer or invoice...',
                        prefixIcon: Icon(Icons.search, size: 16),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 32,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.search, size: 14),
                      label: const Text('Search'),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 5),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 5),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [_serialList(), _batchList(), _warrantyList()],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _serialList() {
    if (_serials.isEmpty) {
      return const _EmptyState(
        icon: Icons.numbers_outlined,
        text: 'No serial records found.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(5),
      itemCount: _serials.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final r = _serials[i];
        final warranty = r['warranty_expiry'];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                (r['serial_number'] ?? '?')
                    .toString()
                    .substring(0, 1)
                    .toUpperCase(),
              ),
            ),
            title: Text(
              _value(r['serial_number']),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${_value(r['product_name'])} • ${_value(r['sku'])}\n${_value(r['status'])} • ${_value(r['location_name'])} • Customer: ${_value(r['customer_name'])}${warranty == null ? '' : '\nWarranty: ${_value(warranty)} (${_value(r['warranty_status'])})'}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showSerial(r),
          ),
        );
      },
    );
  }

  Widget _batchList() {
    if (_batches.isEmpty) {
      return const _EmptyState(
        icon: Icons.inventory_2_outlined,
        text: 'No batch records found.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(5),
      itemCount: _batches.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final r = _batches[i];
        return Card(
          child: ListTile(
            leading: Icon(
              r['expired'] == true
                  ? Icons.event_busy_outlined
                  : Icons.inventory_2_outlined,
            ),
            title: Text(
              _value(r['batch_number']),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${_value(r['product_name'])} • ${_value(r['sku'])}\nQty: ${_value(r['quantity'])} • Expiry: ${_value(r['expiry_on'])} • Supplier: ${_value(r['supplier_name'])}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showBatch(r),
          ),
        );
      },
    );
  }

  Widget _warrantyList() {
    if (_warranties.isEmpty) {
      return const _EmptyState(
        icon: Icons.verified_user_outlined,
        text: 'No warranty records found.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(5),
      itemCount: _warranties.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final r = _warranties[i];
        final identifier = r['serial_number'] ?? r['batch_number'] ?? '-';
        return Card(
          child: ListTile(
            leading: Icon(
              r['status'] == 'expired'
                  ? Icons.verified_user_outlined
                  : Icons.verified_outlined,
            ),
            title: Text(
              '${_value(r['product_name'])} • $identifier',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Customer: ${_value(r['customer_name'])} • Sale: ${_value(r['sale_number'])}\n${_value(r['warranty_start'])} → ${_value(r['warranty_expiry'])} • ${_value(r['status'])}',
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 48), const SizedBox(height: 12), Text(text)],
    ),
  );
}

class _HistoryDialog extends StatelessWidget {
  final String title;
  final Map<String, dynamic> detail;
  const _HistoryDialog({required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    final header = detail['serial'] is Map
        ? Map<String, dynamic>.from(detail['serial'] as Map)
        : detail['batch'] is Map
        ? Map<String, dynamic>.from(detail['batch'] as Map)
        : <String, dynamic>{};
    final events = (detail['events'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final warranties = (detail['warranties'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 760,
        height: 560,
        child: ListView(
          children: [
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: header.entries
                  .where(
                    (e) => !const [
                      'serial_id',
                      'batch_id',
                      'variant_id',
                    ].contains(e.key),
                  )
                  .map(
                    (e) => Chip(
                      label: Text(
                        '${e.key.replaceAll('_', ' ')}: ${e.value ?? '-'}',
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (warranties.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'Warranty',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              ...warranties.map(
                (w) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.verified_user_outlined),
                  title: Text(
                    '${w['warranty_start'] ?? '-'} → ${w['warranty_expiry'] ?? '-'}',
                  ),
                  subtitle: Text(
                    '${w['customer_name'] ?? '-'} • ${w['sale_number'] ?? '-'} • ${w['status'] ?? '-'}',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No events.'),
              ),
            ...events.map(
              (e) => ListTile(
                dense: true,
                leading: const Icon(Icons.history),
                title: Text(
                  '${e['event_type'] ?? '-'} • Qty ${e['quantity'] ?? '-'}',
                ),
                subtitle: Text(
                  '${e['created_at'] ?? '-'} • ${e['location_name'] ?? '-'}\n${e['supplier_name'] ?? e['customer_name'] ?? ''} ${e['purchase_number'] ?? e['sale_number'] ?? e['reference_number'] ?? ''}',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
