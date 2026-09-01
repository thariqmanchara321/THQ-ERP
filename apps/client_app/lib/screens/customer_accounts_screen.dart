import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/customer_account_service.dart';
import '../services/location_scope_service.dart';
import '../widgets/customer_account_dialog.dart';

class CustomerAccountsScreen extends StatefulWidget {
  final ClientSession session;

  const CustomerAccountsScreen({super.key, required this.session});

  @override
  State<CustomerAccountsScreen> createState() => _CustomerAccountsScreenState();
}

class _CustomerAccountsScreenState extends State<CustomerAccountsScreen> {
  final CustomerAccountService _service = CustomerAccountService();
  final TextEditingController _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  bool get _canReceive =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('payments.receive') ||
      widget.session.hasPermission('sales.manage');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;

  String _money(dynamic value) {
    final amount = _number(value);
    return widget.session.currencyCode == 'INR'
        ? '₹${amount.toStringAsFixed(2)}'
        : '${widget.session.currencyCode} ${amount.toStringAsFixed(2)}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.accounts(
        tenantId: widget.session.business.id,
        query: _search.text,
        limit: 1000,
      );
      if (mounted) setState(() => _rows = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerAccountDialog(
        tenantId: widget.session.business.id,
        customerId: row['customer_id'].toString(),
        customerName: row['customer_name']?.toString() ?? 'Customer',
        currencyCode: widget.session.currencyCode,
        locationId: LocationScopeService.currentForCreate(widget.session),
        deviceId: widget.session.device?.deviceId,
        canReceive: _canReceive,
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final totalOutstanding = _rows.fold<double>(
      0,
      (sum, row) => sum + _number(row['outstanding']),
    );
    final dueCustomers =
        _rows.where((row) => _number(row['outstanding']) > 0.005).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Customer Receivables')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      labelText: 'Search customer / phone / customer ID',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.search),
                  label: const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 720;
                final outstandingCard = Card(
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: const Text('Outstanding in your permitted scope'),
                    trailing: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 190),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          _money(totalOutstanding),
                          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                );
                final countCard = Card(
                  child: ListTile(
                    leading: const Icon(Icons.people_outline),
                    title: const Text('Customers with balance'),
                    trailing: Text(
                      '$dueCustomers',
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                    ),
                  ),
                );
                if (narrow) return Column(children: [outstandingCard, countCard]);
                return Row(
                  children: [
                    Expanded(child: outstandingCard),
                    const SizedBox(width: 12),
                    SizedBox(width: 280, child: countCard),
                  ],
                );
              },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? const Center(child: Text('No customer accounts found.'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            itemCount: _rows.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final row = _rows[index];
                              final outstanding = _number(row['outstanding']);
                              final customerName =
                                  row['customer_name']?.toString() ?? 'Customer';
                              final first = customerName.trim().isEmpty
                                  ? '?'
                                  : customerName.trim().characters.first;
                              return Card(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final narrow = constraints.maxWidth < 720;
                                    final identity = Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(child: Text(first.toUpperCase())),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(customerName, style: const TextStyle(fontWeight: FontWeight.w800)),
                                              const SizedBox(height: 3),
                                              Text('${row['public_id'] ?? ''} • ${row['phone'] ?? ''}'),
                                              Text('${row['open_invoice_count'] ?? 0} open invoice(s) • Last sale ${row['last_sale_date'] ?? '-'}'),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                    final amountBlock = ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 190),
                                      child: Column(
                                        crossAxisAlignment: narrow ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                                        children: [
                                          const Text('Outstanding', style: TextStyle(fontSize: 11)),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: narrow ? Alignment.centerLeft : Alignment.centerRight,
                                            child: Text(
                                              _money(outstanding),
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w900,
                                                color: outstanding > 0.005 ? Colors.orange.shade800 : Colors.green.shade700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                    final accountButton = FilledButton.tonalIcon(
                                      onPressed: () => _open(row),
                                      icon: const Icon(Icons.receipt_long_outlined),
                                      label: const Text('Account'),
                                    );
                                    return Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: narrow
                                          ? Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                identity,
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    const SizedBox(width: 52),
                                                    Expanded(child: amountBlock),
                                                    const SizedBox(width: 10),
                                                    accountButton,
                                                  ],
                                                ),
                                              ],
                                            )
                                          : Row(
                                              children: [
                                                Expanded(child: identity),
                                                const SizedBox(width: 18),
                                                amountBlock,
                                                const SizedBox(width: 12),
                                                accountButton,
                                              ],
                                            ),
                                    );
                                  },
                                ),
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
