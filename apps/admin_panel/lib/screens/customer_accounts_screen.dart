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
    final scheme = Theme.of(context).colorScheme;
    final totalOutstanding = _rows.fold<double>(
      0,
      (sum, row) => sum + _number(row['outstanding']),
    );
    final dueCustomers = _rows
        .where((row) => _number(row['outstanding']) > 0.005)
        .length;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: Text(
          '${widget.businessName} | Customer Accounts',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        actions: const [AdminHomeButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Container(
              height: 42,
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
                        hintText: 'Customer, phone or customer ID...',
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
            const SizedBox(height: 5),
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  Expanded(
                    child: _accountMetric(
                      'Customer Outstanding',
                      _money(totalOutstanding),
                      Icons.account_balance_wallet_outlined,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: _accountMetric(
                      'Customers With Balance',
                      '$dueCustomers',
                      Icons.people_outline,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: _accountMetric(
                      'Accounts Loaded',
                      '${_rows.length}',
                      Icons.receipt_long_outlined,
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
                  style: TextStyle(fontSize: 8, color: scheme.onErrorContainer),
                ),
              ),
            ],
            const SizedBox(height: 5),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                  ? const Center(child: Text('No customer accounts found.'))
                  : Container(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: .45,
                            ),
                            child: const Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    'Customer',
                                    style: TextStyle(
                                      fontSize: 8.8,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Open Invoices',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 8.8,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Last Sale',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 8.8,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Outstanding',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 8.8,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 86),
                              ],
                            ),
                          ),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: EdgeInsets.zero,
                                itemCount: _rows.length,
                                itemBuilder: (context, index) {
                                  final row = _rows[index];
                                  final outstanding = _number(
                                    row['outstanding'],
                                  );

                                  return Container(
                                    constraints: const BoxConstraints(
                                      minHeight: 48,
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
                                        Expanded(
                                          flex: 4,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                row['customer_name']
                                                        ?.toString() ??
                                                    'Customer',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 8.8,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              Text(
                                                '${row['public_id'] ?? ''} | '
                                                '${row['phone'] ?? ''}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 7.2,
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            '${row['open_invoice_count'] ?? 0}',
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(
                                              fontSize: 8.2,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            '${row['last_sale_date'] ?? '-'}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(
                                              fontSize: 7.8,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            _money(outstanding),
                                            maxLines: 1,
                                            textAlign: TextAlign.right,
                                            style: TextStyle(
                                              fontSize: 8.7,
                                              fontWeight: FontWeight.w900,
                                              color: outstanding > 0.005
                                                  ? scheme.tertiary
                                                  : scheme.primary,
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 86,
                                          child: FilledButton.tonalIcon(
                                            onPressed: () => _open(row),
                                            icon: const Icon(
                                              Icons.receipt_long_outlined,
                                              size: 13,
                                            ),
                                            label: const Text('Account'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
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
    );
  }

  Widget _accountMetric(String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 7.2,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
