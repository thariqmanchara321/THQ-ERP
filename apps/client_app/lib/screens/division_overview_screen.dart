import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/division_overview_service.dart';

class DivisionOverviewScreen extends StatefulWidget {
  final ClientSession session;
  const DivisionOverviewScreen({super.key, required this.session});

  @override
  State<DivisionOverviewScreen> createState() => _DivisionOverviewScreenState();
}

class _DivisionOverviewScreenState extends State<DivisionOverviewScreen> {
  final DivisionOverviewService _service = DivisionOverviewService();
  late DateTime _from;
  late DateTime _to;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
    _load();
  }

  void _load() {
    _future = _service.load(
      mainTenantId: widget.session.business.id,
      from: _from,
      to: _to,
    );
  }

  String _money(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse('$value') ?? 0;
    return widget.session.currencyCode == 'INR'
        ? '₹${amount.toStringAsFixed(2)}'
        : '${widget.session.currencyCode} ${amount.toStringAsFixed(2)}';
  }

  Future<void> _pick(bool from) async {
    final date = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null) return;
    setState(() {
      if (from) {
        _from = date;
      } else {
        _to = date;
      }
      if (_from.isAfter(_to)) {
        final temp = _from;
        _from = _to;
        _to = temp;
      }
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: EdgeInsets.all(constraints.maxWidth < 700 ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Division Overview',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Merged summary across the MAIN business and child businesses.',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(_load),
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pick(true),
                  icon: const Icon(Icons.date_range),
                  label: Text('${_from.day}/${_from.month}/${_from.year}'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pick(false),
                  icon: const Icon(Icons.event),
                  label: Text('${_to.day}/${_to.month}/${_to.year}'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final data = snapshot.data ?? const <String, dynamic>{};
                  if (data['has_division'] != true) {
                    return const Center(
                      child: Text(
                        'This business is not configured as the MAIN business of a Business Division.',
                      ),
                    );
                  }
                  final businesses = (data['businesses'] as List? ?? const [])
                      .whereType<Map>()
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList();
                  return ListView(
                    children: [
                      Text(
                        data['division_name']?.toString() ??
                            'Business Division',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _Metric(
                            'Sales',
                            _money(data['sales']),
                            Icons.trending_up,
                          ),
                          _Metric(
                            'Purchases',
                            _money(data['purchases']),
                            Icons.shopping_cart_outlined,
                          ),
                          _Metric(
                            'Expenses',
                            _money(data['expenses']),
                            Icons.payments_outlined,
                          ),
                          _Metric(
                            'Receivables',
                            _money(data['receivables']),
                            Icons.call_received,
                          ),
                          _Metric(
                            'Payables',
                            _money(data['payables']),
                            Icons.call_made,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ...businesses.map(
                        (row) => Card(
                          margin: const EdgeInsets.only(bottom: 9),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Wrap(
                              spacing: 18,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: 230,
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        child: Icon(
                                          row['member_type'] == 'main'
                                              ? Icons.business
                                              : Icons.store_outlined,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              row['name']?.toString() ?? '',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            Text(
                                              row['member_type'] == 'main'
                                                  ? 'MAIN Business'
                                                  : 'Child Business',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _SmallValue('Sales', _money(row['sales'])),
                                _SmallValue(
                                  'Purchases',
                                  _money(row['purchases']),
                                ),
                                _SmallValue(
                                  'Expenses',
                                  _money(row['expenses']),
                                ),
                                _SmallValue(
                                  'To receive',
                                  _money(row['receivables']),
                                ),
                                _SmallValue('To pay', _money(row['payables'])),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _Metric(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) => Container(
    width: 190,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
            ],
          ),
        ),
      ],
    ),
  );
}

class _SmallValue extends StatelessWidget {
  final String label;
  final String value;
  const _SmallValue(this.label, this.value);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 115,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
