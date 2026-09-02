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
    return Scaffold(
      appBar: AppBar(
        title: Text('CRM • ${widget.customer.name}'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _metric(
                        'Gross Sales',
                        _money(summary['gross_sales']),
                        Icons.point_of_sale_outlined,
                      ),
                      _metric(
                        'Returns',
                        _money(summary['returns']),
                        Icons.keyboard_return_outlined,
                      ),
                      _metric(
                        'Payments',
                        _money(summary['payments']),
                        Icons.payments_outlined,
                      ),
                      _metric(
                        'Outstanding',
                        _money(summary['outstanding_sales']),
                        Icons.account_balance_wallet_outlined,
                      ),
                      _metric(
                        'Loan Receivable',
                        _money(summary['loan_receivable']),
                        Icons.south_west_outlined,
                      ),
                      _metric(
                        'Loan Payable',
                        _money(summary['loan_payable']),
                        Icons.north_east_outlined,
                      ),
                      _metric(
                        'Loyalty',
                        '${crm['loyalty_points'] ?? 0} pts',
                        Icons.stars_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Customer Profile',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _row('Customer ID', widget.customer.publicId),
                          _row('Phone', widget.customer.phone ?? '—'),
                          _row('Email', widget.customer.email ?? '—'),
                          _row(
                            'GSTIN / Tax ID',
                            widget.customer.taxNumber ?? '—',
                          ),
                          _row(
                            'Credit Limit',
                            _money(widget.customer.creditLimit),
                          ),
                          _row(
                            'Customer Group',
                            crm['group_name']?.toString() ?? '—',
                          ),
                          _row(
                            'Group Discount',
                            '${crm['group_discount_percent'] ?? 0}%',
                          ),
                          _row('Birthday', crm['birthday']?.toString() ?? '—'),
                          _row(
                            'Anniversary',
                            crm['anniversary']?.toString() ?? '—',
                          ),
                          _row(
                            'Last Sale',
                            summary['last_sale_date']?.toString() ?? '—',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Customer-specific pricing, statements, sales history, returns, payments and loans remain linked to this customer through the existing THQ workspaces.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _metric(String label, String value, IconData icon) => SizedBox(
    width: 180,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 170,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
