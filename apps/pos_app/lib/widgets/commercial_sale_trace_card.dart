import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/commercial_pricing_service.dart';

class CommercialSaleTraceCard extends StatefulWidget {
  const CommercialSaleTraceCard({
    super.key,
    required this.session,
    required this.saleId,
  });

  final ClientSession session;
  final String saleId;

  @override
  State<CommercialSaleTraceCard> createState() =>
      _CommercialSaleTraceCardState();
}

class _CommercialSaleTraceCardState extends State<CommercialSaleTraceCard> {
  final CommercialPricingService _service = CommercialPricingService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _trace;

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _number(dynamic value) =>
      (value as num?)?.toDouble() ?? double.tryParse('$value') ?? 0.0;

  String _money(dynamic value) {
    final amount = _number(value);
    if (widget.session.currencyCode == 'INR') {
      return 'â‚¹${amount.toStringAsFixed(2)}';
    }
    return '${widget.session.currencyCode} ${amount.toStringAsFixed(2)}';
  }

  String _pretty(dynamic value) => (value?.toString() ?? '-')
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part.substring(0, 1).toUpperCase()}${part.substring(1)}',
      )
      .join(' ');

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trace = await _service.saleTrace(
        tenantId: widget.session.business.id,
        saleId: widget.saleId,
      );
      if (mounted) setState(() => _trace = trace);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  List<Map<String, dynamic>> _list(dynamic value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);

  Widget _evidenceChip(BuildContext context, String label, bool ok) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        ok ? Icons.check_circle : Icons.error_outline,
        size: 14,
        color: ok ? scheme.primary : scheme.error,
      ),
      label: Text(label),
    );
  }

  Widget _row(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 155,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: _loading
            ? const SizedBox(
                height: 56,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Commercial / GST / Accounting Trace',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _error!,
                    style: TextStyle(color: scheme.error, fontSize: 11),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, size: 15),
                      label: const Text('Retry'),
                    ),
                  ),
                ],
              )
            : _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final trace = _trace ?? const <String, dynamic>{};
    final commercial = _map(trace['commercial_summary']);
    final restaurant = _map(trace['restaurant_order']);
    final gst = _map(trace['gst_snapshot']);
    final journal = _map(trace['journal']);
    final evidence = _map(trace['evidence']) ?? const <String, dynamic>{};
    final kots = _list(trace['kots']);
    final payments = _list(trace['payments']);
    final charges = _list(commercial?['charge_breakdown']);

    final paymentTotal = payments.fold<double>(
      0,
      (sum, row) => sum + _number(row['amount']),
    );

    final chain = restaurant != null
        ? 'Restaurant ${restaurant['order_number'] ?? ''}  â†’  '
              '${kots.isEmpty ? 'KOT' : '${kots.length} KOT(s)'}  â†’  '
              'Sale  â†’  GST Snapshot  â†’  Payments  â†’  Journal'
        : 'Sale  â†’  GST Snapshot  â†’  Payments  â†’  Journal';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.account_tree_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 7),
            const Expanded(
              child: Text(
                'Commercial / GST / Accounting Trace',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
            IconButton(
              tooltip: 'Refresh trace',
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        Text(
          chain,
          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            _evidenceChip(
              context,
              'Commercial',
              evidence['commercial_summary'] == true,
            ),
            if (restaurant != null)
              _evidenceChip(
                context,
                'Restaurant Source',
                evidence['restaurant_source'] == true,
              ),
            _evidenceChip(
              context,
              'GST Snapshot',
              evidence['gst_snapshot'] == true,
            ),
            _evidenceChip(context, 'Journal', evidence['journal'] == true),
            _evidenceChip(context, 'Payments', evidence['payments'] == true),
          ],
        ),
        if (commercial != null) ...[
          const Divider(height: 20),
          _row('Order Type', _pretty(commercial['order_type'])),
          _row(
            'Document Discount',
            '${_pretty(commercial['discount_type'])} â€¢ '
                '${_money(commercial['document_discount_total'])}',
          ),
          _row(
            'Classified Charges',
            _money(commercial['classified_charge_total']),
            strong: true,
          ),
          if (charges.isNotEmpty) ...[
            const SizedBox(height: 5),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: charges.map((row) {
                final name =
                    row['name']?.toString() ??
                    row['code']?.toString() ??
                    'Charge';
                return Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('$name ${_money(row['line_total'])}'),
                );
              }).toList(),
            ),
          ],
        ],
        const Divider(height: 20),
        if (restaurant != null) ...[
          _row(
            'Restaurant Source',
            '${restaurant['order_number'] ?? '-'} â€¢ '
                '${_pretty(restaurant['order_type'])} â€¢ '
                '${_pretty(restaurant['status'])}',
          ),
          _row('KOT Evidence', '${kots.length} KOT record(s)'),
        ],
        _row(
          'GST Evidence',
          gst == null
              ? 'Missing'
              : '${gst['document_number'] ?? gst['id']} â€¢ '
                    '${gst['engine_version'] ?? 'GST engine'} â€¢ '
                    'Tax ${_money(gst['tax_collected_total'])}',
          strong: gst != null,
        ),
        _row(
          'Payments',
          '${payments.length} allocation(s) â€¢ ${_money(paymentTotal)}',
        ),
        _row(
          'Accounting Journal',
          journal == null
              ? 'Missing'
              : '${journal['entry_number'] ?? journal['id']} â€¢ '
                    '${_pretty(journal['status'])} â€¢ '
                    'Dr ${_money(journal['debit_total'])} / '
                    'Cr ${_money(journal['credit_total'])}',
          strong: journal != null,
        ),
      ],
    );
  }
}
