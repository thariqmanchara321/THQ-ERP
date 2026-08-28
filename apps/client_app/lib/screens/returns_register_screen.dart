import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/location_scope_service.dart';
import '../services/returns_service.dart';

class ReturnsRegisterScreen extends StatefulWidget {
  final ClientSession session;
  const ReturnsRegisterScreen({super.key, required this.session});

  @override
  State<ReturnsRegisterScreen> createState() => _ReturnsRegisterScreenState();
}

class _ReturnsRegisterScreenState extends State<ReturnsRegisterScreen> {
  final _service = ReturnsService();
  final _search = TextEditingController();
  late DateTime _from;
  late DateTime _to;
  String _type = 'all';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.register(
        tenantId: widget.session.business.id,
        from: _from,
        to: _to,
        locationId: LocationScopeService.currentForRead(widget.session),
        type: _type,
        query: _search.text,
      );
      if (mounted) setState(() => _rows = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(bool from) async {
    final value = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (value == null) return;
    setState(() {
      if (from) {
        _from = value;
      } else {
        _to = value;
      }
      if (_from.isAfter(_to)) {
        final x = _from;
        _from = _to;
        _to = x;
      }
    });
    await _load();
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
  String _money(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse('$value') ?? 0;
    return widget.session.currencyCode == 'INR'
        ? '₹${amount.toStringAsFixed(2)}'
        : '${widget.session.currencyCode} ${amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final sales = _rows
        .where((row) => row['return_type'] == 'sale_return')
        .fold<double>(
          0,
          (sum, row) => sum + ((row['grand_total'] as num?)?.toDouble() ?? 0),
        );
    final purchases = _rows
        .where((row) => row['return_type'] == 'purchase_return')
        .fold<double>(
          0,
          (sum, row) => sum + ((row['grand_total'] as num?)?.toDouble() ?? 0),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Returns Register')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _search,
                    onSubmitted: (_) => _load(),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Return no., invoice, customer, supplier…',
                    ),
                  ),
                ),
                DropdownButton<String>(
                  value: _type,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Returns')),
                    DropdownMenuItem(
                      value: 'sale',
                      child: Text('Sales Returns'),
                    ),
                    DropdownMenuItem(
                      value: 'purchase',
                      child: Text('Purchase Returns'),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => _type = value);
                    await _load();
                  },
                ),
                OutlinedButton.icon(
                  onPressed: () => _pick(true),
                  icon: const Icon(Icons.date_range, size: 17),
                  label: Text(_date(_from)),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pick(false),
                  icon: const Icon(Icons.date_range, size: 17),
                  label: Text(_date(_to)),
                ),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MiniMetric('Rows', '${_rows.length}'),
                const SizedBox(width: 8),
                _MiniMetric('Sales Returns', _money(sales)),
                const SizedBox(width: 8),
                _MiniMetric('Purchase Returns', _money(purchases)),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!, textAlign: TextAlign.center))
                  : _rows.isEmpty
                  ? const Center(
                      child: Text('No returns found for this period/store.'),
                    )
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        final sale = row['return_type'] == 'sale_return';
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            sale
                                ? Icons.assignment_return_outlined
                                : Icons.keyboard_return_outlined,
                            size: 19,
                          ),
                          title: Text(
                            '${row['return_number'] ?? '-'} • ${row['party'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            '${sale ? 'Sales Return' : 'Purchase Return'} • ${row['reference'] ?? ''} • ${row['location_name'] ?? ''}${row['device_name'] == null ? '' : ' • ${row['device_name']}'}',
                            style: const TextStyle(fontSize: 10),
                          ),
                          trailing: Text(
                            _money(row['grand_total']),
                            style: const TextStyle(fontWeight: FontWeight.w800),
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

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  const _MiniMetric(this.label, this.value);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9.5)),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    ),
  );
}
