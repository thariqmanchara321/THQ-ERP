import 'package:flutter/material.dart';

import '../services/customer_account_service.dart';
import '../widgets/customer_account_dialog.dart';
import '../widgets/admin_home_button.dart';

class CustomerAccountsScreen extends StatefulWidget {
  final String tenantId;
  final String businessName;
  final String currencyCode;

  const CustomerAccountsScreen({
    super.key,
    required this.tenantId,
    required this.businessName,
    this.currencyCode = 'INR',
  });

  @override
  State<CustomerAccountsScreen> createState() => _CustomerAccountsScreenState();
}

class _CustomerAccountsScreenState extends State<CustomerAccountsScreen> {
  final CustomerAccountService _service = CustomerAccountService();
  final TextEditingController _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

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
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  String _money(dynamic value) {
    final amount = _number(value);
    return widget.currencyCode == 'INR'
        ? '₹${amount.toStringAsFixed(2)}'
        : '${widget.currencyCode} ${amount.toStringAsFixed(2)}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.accounts(
        tenantId: widget.tenantId,
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
        tenantId: widget.tenantId,
        customerId: row['customer_id'].toString(),
        customerName: row['customer_name']?.toString() ?? 'Customer',
        currencyCode: widget.currencyCode,
        canReceive: true,
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
    final dueCustomers = _rows.where((row) => _number(row['outstanding']) > 0.005).length;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('${widget.businessName} • Customer Accounts'),
        actions: const [AdminHomeButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
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
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.account_balance_wallet_outlined),
                      title: const Text('Total customer outstanding'),
                      trailing: Text(
                        _money(totalOutstanding),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 260,
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const Text('Customers with balance'),
                      trailing: Text('$dueCustomers', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
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
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final row = _rows[index];
                              final outstanding = _number(row['outstanding']);
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Text((row['customer_name']?.toString() ?? '?').characters.first.toUpperCase()),
                                  ),
                                  title: Text(
                                    row['customer_name']?.toString() ?? 'Customer',
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  subtitle: Text(
                                    '${row['public_id'] ?? ''} • ${row['phone'] ?? ''}\n'
                                    '${row['open_invoice_count'] ?? 0} open invoice(s) • Last sale ${row['last_sale_date'] ?? '-'}',
                                  ),
                                  isThreeLine: true,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          const Text('Outstanding', style: TextStyle(fontSize: 11)),
                                          Text(
                                            _money(outstanding),
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w900,
                                              color: outstanding > 0.005 ? Colors.orange.shade800 : Colors.green.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 12),
                                      FilledButton.tonalIcon(
                                        onPressed: () => _open(row),
                                        icon: const Icon(Icons.receipt_long_outlined),
                                        label: const Text('Account'),
                                      ),
                                    ],
                                  ),
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
