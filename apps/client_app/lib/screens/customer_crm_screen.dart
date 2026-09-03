import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import '../models/customer.dart';

class CustomerCrmScreen extends StatefulWidget {
  final ClientSession session;
  final Customer customer;
  const CustomerCrmScreen({
    super.key,
    required this.session,
    required this.customer,
  });

  @override
  State<CustomerCrmScreen> createState() => _CustomerCrmScreenState();
}

class _CustomerCrmScreenState extends State<CustomerCrmScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};

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
      final raw = await Supabase.instance.client.rpc(
        'customer_crm_profile_v500',
        params: {
          'p_tenant_id': widget.session.business.id,
          'p_customer_id': widget.customer.id,
        },
      );
      _data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(dynamic value) {
    final n = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    return widget.session.currencyCode == 'INR'
        ? '₹${n.toStringAsFixed(2)}'
        : '${widget.session.currencyCode} ${n.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final summary = _data['summary'] is Map
        ? Map<String, dynamic>.from(_data['summary'] as Map)
        : <String, dynamic>{};
    final crm = _data['crm'] is Map
        ? Map<String, dynamic>.from(_data['crm'] as Map)
        : <String, dynamic>{};
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 46,
        title: Text(
          'CRM - ${widget.customer.name}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final metrics = <(String, String, IconData)>[
                    (
                      'Gross Sales',
                      _money(summary['gross_sales']),
                      Icons.point_of_sale_outlined,
                    ),
                    (
                      'Returns',
                      _money(summary['returns']),
                      Icons.keyboard_return_outlined,
                    ),
                    (
                      'Payments',
                      _money(summary['payments']),
                      Icons.payments_outlined,
                    ),
                    (
                      'Outstanding',
                      _money(summary['outstanding_sales']),
                      Icons.account_balance_wallet_outlined,
                    ),
                    (
                      'Loan Receivable',
                      _money(summary['loan_receivable']),
                      Icons.south_west_outlined,
                    ),
                    (
                      'Loan Payable',
                      _money(summary['loan_payable']),
                      Icons.north_east_outlined,
                    ),
                    (
                      'Loyalty',
                      '${crm['loyalty_points'] ?? 0} pts',
                      Icons.stars_outlined,
                    ),
                  ];

                  final columns = constraints.maxWidth >= 900
                      ? 4
                      : constraints.maxWidth >= 600
                      ? 3
                      : 2;
                  const gap = 6.0;
                  final metricWidth =
                      (constraints.maxWidth - ((columns - 1) * gap)) / columns;

                  return Column(
                    children: [
                      Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: metrics
                            .map(
                              (metric) => SizedBox(
                                width: metricWidth,
                                child: _metric(metric.$1, metric.$2, metric.$3),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              Container(
                                height: 36,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                color: scheme.surfaceContainerHighest,
                                child: const Row(
                                  children: [
                                    Icon(Icons.person_outline, size: 16),
                                    SizedBox(width: 7),
                                    Text(
                                      'CUSTOMER PROFILE',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: .4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    children: [
                                      _row(
                                        'Customer ID',
                                        widget.customer.publicId,
                                      ),
                                      _row(
                                        'Phone',
                                        widget.customer.phone ?? 'â€”',
                                      ),
                                      _row(
                                        'Email',
                                        widget.customer.email ?? 'â€”',
                                      ),
                                      _row(
                                        'GSTIN / Tax ID',
                                        widget.customer.taxNumber ?? 'â€”',
                                      ),
                                      _row(
                                        'Credit Limit',
                                        _money(widget.customer.creditLimit),
                                      ),
                                      _row(
                                        'Customer Group',
                                        crm['group_name']?.toString() ?? 'â€”',
                                      ),
                                      _row(
                                        'Group Discount',
                                        '${crm['group_discount_percent'] ?? 0}%',
                                      ),
                                      _row(
                                        'Birthday',
                                        crm['birthday']?.toString() ?? 'â€”',
                                      ),
                                      _row(
                                        'Anniversary',
                                        crm['anniversary']?.toString() ?? 'â€”',
                                      ),
                                      _row(
                                        'Last Sale',
                                        summary['last_sale_date']?.toString() ??
                                            'â€”',
                                      ),
                                      const SizedBox(height: 10),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(9),
                                        decoration: BoxDecoration(
                                          color: scheme.surfaceContainerHighest
                                              .withValues(alpha: .45),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'Customer-specific pricing, statements, sales history, returns, payments and loans remain linked through the existing THQ workspaces.',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _metric(String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 14, color: scheme.primary),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.3,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 38),
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
