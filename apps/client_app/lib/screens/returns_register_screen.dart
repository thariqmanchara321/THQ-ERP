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
    final scheme = Theme.of(context).colorScheme;
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
      appBar: AppBar(
        toolbarHeight: 46,
        title: const Text(
          'Returns Register',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 760;
                  final search = TextField(
                    controller: _search,
                    onSubmitted: (_) => _load(),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 17),
                      hintText: 'Return no., invoice, customer, supplier...',
                    ),
                  );
                  final type = DropdownButtonFormField<String>(
                    initialValue: _type,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text('All Returns'),
                      ),
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
                  );

                  if (narrow) {
                    return Column(
                      children: [
                        search,
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Expanded(child: type),
                            IconButton(
                              tooltip: 'From ${_date(_from)}',
                              onPressed: () => _pick(true),
                              icon: const Icon(Icons.date_range, size: 18),
                            ),
                            IconButton(
                              tooltip: 'To ${_date(_to)}',
                              onPressed: () => _pick(false),
                              icon: const Icon(Icons.event, size: 18),
                            ),
                            IconButton(
                              tooltip: 'Refresh',
                              onPressed: _load,
                              icon: const Icon(Icons.refresh, size: 18),
                            ),
                          ],
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(flex: 4, child: search),
                      const SizedBox(width: 6),
                      SizedBox(width: 160, child: type),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        onPressed: () => _pick(true),
                        icon: const Icon(Icons.date_range, size: 15),
                        label: Text(_date(_from)),
                      ),
                      const SizedBox(width: 5),
                      OutlinedButton.icon(
                        onPressed: () => _pick(false),
                        icon: const Icon(Icons.event, size: 15),
                        label: Text(_date(_to)),
                      ),
                      IconButton(
                        tooltip: 'Refresh',
                        visualDensity: VisualDensity.compact,
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 18),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  Expanded(child: _MiniMetric('Rows', '${_rows.length}')),
                  const SizedBox(width: 5),
                  Expanded(child: _MiniMetric('Sales Returns', _money(sales))),
                  const SizedBox(width: 5),
                  Expanded(
                    child: _MiniMetric('Purchase Returns', _money(purchases)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!, textAlign: TextAlign.center))
                  : _rows.isEmpty
                  ? const Center(
                      child: Text('No returns found for this period/store.'),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 720;
                          return Column(
                            children: [
                              if (!compact)
                                Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                  ),
                                  color: scheme.surfaceContainerHighest,
                                  child: const Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          'Return',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          'Type',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 4,
                                        child: Text(
                                          'Party / Reference',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          'Store / Device',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          'Amount',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Expanded(
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: _rows.length,
                                  itemBuilder: (context, index) {
                                    final row = _rows[index];
                                    final sale =
                                        row['return_type'] == 'sale_return';
                                    if (compact) {
                                      return Container(
                                        constraints: const BoxConstraints(
                                          minHeight: 50,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                              color: scheme.outlineVariant,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              sale
                                                  ? Icons
                                                        .assignment_return_outlined
                                                  : Icons
                                                        .keyboard_return_outlined,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 7),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${row['return_number'] ?? '-'} | ${row['party'] ?? ''}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${sale ? 'Sales Return' : 'Purchase Return'} | ${row['reference'] ?? ''}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Text(
                                              _money(row['grand_total']),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    Widget cell(
                                      Widget child,
                                      int flex, {
                                      Alignment alignment =
                                          Alignment.centerLeft,
                                    }) => Expanded(
                                      flex: flex,
                                      child: Align(
                                        alignment: alignment,
                                        child: child,
                                      ),
                                    );
                                    return Container(
                                      constraints: const BoxConstraints(
                                        minHeight: 42,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: scheme.outlineVariant,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          cell(
                                            Text(
                                              row['return_number']
                                                      ?.toString() ??
                                                  '-',
                                              maxLines: 1,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            2,
                                          ),
                                          cell(
                                            Text(
                                              sale
                                                  ? 'Sales Return'
                                                  : 'Purchase Return',
                                              maxLines: 1,
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                              ),
                                            ),
                                            2,
                                          ),
                                          cell(
                                            Text(
                                              '${row['party'] ?? ''} | ${row['reference'] ?? ''}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                            ),
                                            4,
                                          ),
                                          cell(
                                            Text(
                                              '${row['location_name'] ?? ''}${row['device_name'] == null ? '' : ' | ${row['device_name']}'}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                            3,
                                          ),
                                          cell(
                                            Text(
                                              _money(row['grand_total']),
                                              maxLines: 1,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            2,
                                            alignment: Alignment.centerRight,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
