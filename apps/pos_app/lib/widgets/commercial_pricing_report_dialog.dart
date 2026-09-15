import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/commercial_pricing_service.dart';

class CommercialPricingReportDialog extends StatefulWidget {
  const CommercialPricingReportDialog({
    super.key,
    required this.session,
    required this.from,
    required this.to,
  });

  final ClientSession session;
  final DateTime from;
  final DateTime to;

  @override
  State<CommercialPricingReportDialog> createState() =>
      _CommercialPricingReportDialogState();
}

class _CommercialPricingReportDialogState
    extends State<CommercialPricingReportDialog> {
  final CommercialPricingService _service = CommercialPricingService();

  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _service.commercialReport(
      tenantId: widget.session.business.id,
      from: widget.from,
      to: widget.to,
    );
  }

  void _reload() => setState(_load);

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

  List<Map<String, dynamic>> _list(dynamic value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-${value.year}';

  Widget _metric(
    BuildContext context,
    String label,
    String value,
    String caption,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 180,
      height: 78,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 8.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(22),
      child: SizedBox(
        width: 1120,
        height: 760,
        child: Column(
          children: [
            Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.price_change_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Commercial Pricing Report',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${_date(widget.from)} â†’ ${_date(widget.to)}',
                          style: TextStyle(
                            fontSize: 9,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  final data = snapshot.data ?? const {};
                  final summary = _map(data['summary']);
                  final orderTypes = _list(data['order_types']);
                  final discounts = _list(data['discount_types']);
                  final charges = _list(data['charges']);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            _metric(
                              context,
                              'Commercial Sales',
                              _money(summary['sales_total']),
                              '${summary['sale_count'] ?? 0} sale(s)',
                            ),
                            _metric(
                              context,
                              'Order Discounts',
                              _money(summary['document_discount_total']),
                              '${summary['discounted_sale_count'] ?? 0} discounted',
                            ),
                            _metric(
                              context,
                              'Classified Charges',
                              _money(summary['classified_charge_total']),
                              '${summary['charged_sale_count'] ?? 0} charged',
                            ),
                            _metric(
                              context,
                              'Commercial Tax',
                              _money(summary['tax_total']),
                              'Authoritative GST snapshots',
                            ),
                            _metric(
                              context,
                              'Restaurant',
                              '${summary['restaurant_sale_count'] ?? 0}',
                              'Restaurant commercial sales',
                            ),
                            _metric(
                              context,
                              'Normal POS',
                              '${summary['normal_sale_count'] ?? 0}',
                              'Normal commercial sales',
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _section(
                          context,
                          'Order Type Breakdown',
                          orderTypes.isEmpty
                              ? const Text('No commercial sales in this range.')
                              : Column(
                                  children: orderTypes
                                      .map(
                                        (row) => _dataRow(
                                          _pretty(row['order_type']),
                                          '${row['sale_count'] ?? 0} sale(s)',
                                          _money(row['sales_total']),
                                          'Discount ${_money(row['discount_total'])} â€¢ '
                                              'Charges ${_money(row['charge_total'])}',
                                        ),
                                      )
                                      .toList(),
                                ),
                        ),
                        const SizedBox(height: 10),
                        _section(
                          context,
                          'Discount Breakdown',
                          discounts.isEmpty
                              ? const Text('No discount data in this range.')
                              : Wrap(
                                  spacing: 7,
                                  runSpacing: 7,
                                  children: discounts
                                      .map(
                                        (row) => Chip(
                                          label: Text(
                                            '${_pretty(row['discount_type'])}: '
                                            '${_money(row['discount_total'])} '
                                            '(${row['sale_count'] ?? 0})',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                        ),
                        const SizedBox(height: 10),
                        _section(
                          context,
                          'GST-Classified Charges',
                          charges.isEmpty
                              ? const Text(
                                  'No packaging/delivery/service charges '
                                  'were posted in this range.',
                                )
                              : Column(
                                  children: charges
                                      .map(
                                        (row) => _dataRow(
                                          row['name']?.toString() ??
                                              row['code']?.toString() ??
                                              'Charge',
                                          '${_pretty(row['kind'])} â€¢ '
                                              'Qty ${_number(row['quantity']).toStringAsFixed(2)}',
                                          _money(row['line_total']),
                                          'Taxable ${_money(row['taxable_total'])} â€¢ '
                                              'GST ${_money(row['tax_total'])} â€¢ '
                                              '${row['application_count'] ?? 0} application(s)',
                                        ),
                                      )
                                      .toList(),
                                ),
                        ),
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

  Widget _section(BuildContext context, String title, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _dataRow(String title, String subtitle, String value, String detail) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(subtitle, style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(detail, style: const TextStyle(fontSize: 10)),
          ),
          SizedBox(
            width: 120,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}
