import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/payment_pending.dart';
import '../services/payment_center_service.dart';
import 'party_statement_screen.dart';
import 'purchase_detail_screen.dart';
import 'sale_detail_screen.dart';

class PaymentCenterScreen extends StatefulWidget {
  final ClientSession session;
  const PaymentCenterScreen({super.key, required this.session});

  @override
  State<PaymentCenterScreen> createState() => _PaymentCenterScreenState();
}

class _PaymentCenterScreenState extends State<PaymentCenterScreen> {
  final _service = PaymentCenterService();
  final _query = TextEditingController();
  late Future<PendingPaymentsData> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _load() {
    _future = _service.load(widget.session, query: _query.text.trim());
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  String _m(double v) => widget.session.currencyCode == 'INR'
      ? 'INR ${v.toStringAsFixed(2)}'
      : '${widget.session.currencyCode} ${v.toStringAsFixed(2)}';

  Future<void> _openParty(PartyPendingSummary party) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PartyPaymentDetailScreen(
          session: widget.session,
          summary: party,
          service: _service,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 25,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pending Payments',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Customer receivables and supplier payables',
                        style: TextStyle(
                          fontSize: 8.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh balances',
                  visualDensity: VisualDensity.compact,
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => setState(_load),
              decoration: InputDecoration(
                hintText:
                    'Search customer, supplier, phone, email or tracking ID...',
                prefixIcon: const Icon(Icons.search, size: 16),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _query.clear();
                          setState(_load);
                        },
                        icon: const Icon(Icons.close, size: 15),
                      ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: FutureBuilder<PendingPaymentsData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: SelectableText(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final data = snapshot.data!;
                final receive = _PartyPane(
                  title: 'Customers | To Receive',
                  subtitle: '${data.receivables.length} account(s)',
                  icon: Icons.south_west_rounded,
                  amount: data.totalReceivable,
                  money: _m,
                  rows: data.receivables,
                  onOpen: _openParty,
                );
                final pay = _PartyPane(
                  title: 'Suppliers | To Pay',
                  subtitle: '${data.payables.length} account(s)',
                  icon: Icons.north_east_rounded,
                  amount: data.totalPayable,
                  money: _m,
                  rows: data.payables,
                  onOpen: _openParty,
                );

                return LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 850) {
                      return Column(
                        children: [
                          Expanded(child: receive),
                          const SizedBox(height: 5),
                          Expanded(child: pay),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: receive),
                        const SizedBox(width: 5),
                        Expanded(child: pay),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PartyPane extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final double amount;
  final String Function(double) money;
  final List<PartyPendingSummary> rows;
  final void Function(PartyPendingSummary) onOpen;

  const _PartyPane({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.amount,
    required this.money,
    required this.rows,
    required this.onOpen,
  });

  String _d(DateTime? value) {
    if (value == null) return 'No due date';
    return '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            color: scheme.surfaceContainerHighest.withValues(alpha: .42),
            child: Row(
              children: [
                Icon(icon, size: 15, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 7.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  money(amount),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Text(
                      'Nothing pending.',
                      style: TextStyle(fontSize: 9),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final isCustomer = row.partyType == 'customer';
                      final breakdown = isCustomer
                          ? 'Sales ${money(row.salesOutstanding)} | '
                                'Loans ${money(row.loanOutstanding)}'
                          : 'Purchases ${money(row.purchaseOutstanding)} | '
                                'Invoices ${money(row.invoiceOutstanding)}'
                                '${row.creditBalance > .005 ? ' | Credit ${money(row.creditBalance)}' : ''}';

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onOpen(row),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 52),
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
                                Container(
                                  width: 27,
                                  height: 27,
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(
                                      alpha: .08,
                                    ),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Icon(
                                    isCustomer
                                        ? Icons.person_outline
                                        : Icons.local_shipping_outlined,
                                    size: 14,
                                    color: scheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row.partyName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 8.8,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        breakdown,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 7.2,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      Text(
                                        '${row.documentCount} open | '
                                        'Due ${_d(row.nextDueDate)}'
                                        '${row.overdue > .005 ? ' | Overdue ${money(row.overdue)}' : ''}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 7,
                                          color: row.overdue > .005
                                              ? scheme.error
                                              : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  money(row.balance),
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 8.8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                const Icon(Icons.chevron_right, size: 15),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PartyPaymentDetailScreen extends StatefulWidget {
  final ClientSession session;
  final PartyPendingSummary summary;
  final PaymentCenterService service;

  const _PartyPaymentDetailScreen({
    required this.session,
    required this.summary,
    required this.service,
  });

  @override
  State<_PartyPaymentDetailScreen> createState() =>
      _PartyPaymentDetailScreenState();
}

class _PartyPaymentDetailScreenState extends State<_PartyPaymentDetailScreen> {
  late Future<PartyPaymentDetail> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = widget.service.detail(
      widget.session,
      partyType: widget.summary.partyType,
      partyId: widget.summary.partyId,
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  String _m(double v) => widget.session.currencyCode == 'INR'
      ? 'INR ${v.toStringAsFixed(2)}'
      : '${widget.session.currencyCode} ${v.toStringAsFixed(2)}';

  String _d(DateTime? value) {
    if (value == null) return '—';
    return '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
  }

  String _label(String value) => value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  Future<void> _openDocument(PartyOpenDocument document) async {
    if (document.sourceType == 'sale') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SaleDetailScreen(
            session: widget.session,
            saleId: document.sourceId,
          ),
        ),
      );
    } else if (document.sourceType == 'purchase') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PurchaseDetailScreen(
            session: widget.session,
            purchaseId: document.sourceId,
          ),
        ),
      );
    }
    if (mounted) await _refresh();
  }

  void _openStatement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PartyStatementScreen(
          session: widget.session,
          partyId: widget.summary.partyId,
          customer: widget.summary.partyType == 'customer',
          title: '${widget.summary.partyName} Statement',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.summary.partyName),
      actions: [
        TextButton.icon(
          onPressed: _openStatement,
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Statement'),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: FutureBuilder<PartyPaymentDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: SelectableText(snapshot.error.toString()));
        }
        final data = snapshot.data!;
        final party = data.party;
        final isCustomer = widget.summary.partyType == 'customer';
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricCard(
                    label: isCustomer ? 'Total To Receive' : 'Net To Pay',
                    value: _m(data.netOutstanding),
                    icon: isCustomer ? Icons.call_received : Icons.call_made,
                  ),
                  _MetricCard(
                    label: 'Gross Outstanding',
                    value: _m(data.grossOutstanding),
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  _MetricCard(
                    label: 'Overdue',
                    value: _m(data.overdue),
                    icon: Icons.warning_amber_rounded,
                    danger: data.overdue > .005,
                  ),
                  if (!isCustomer && data.creditBalance > .005)
                    _MetricCard(
                      label: 'Supplier Credit',
                      value: _m(data.creditBalance),
                      icon: Icons.savings_outlined,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    children: [
                      _Info(
                        label: 'ID',
                        value: party['tracking_code']?.toString() ?? '',
                      ),
                      _Info(
                        label: 'Phone',
                        value: party['phone']?.toString() ?? '',
                      ),
                      _Info(
                        label: 'Email',
                        value: party['email']?.toString() ?? '',
                      ),
                      _Info(
                        label: 'Tax / GST',
                        value: party['tax_number']?.toString() ?? '',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: 'Open Documents'),
                          Tab(text: 'Recent Payments'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _documents(data.documents),
                            _payments(data.recentPayments),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _documents(List<PartyOpenDocument> documents) {
    if (documents.isEmpty) {
      return const Center(child: Text('No open documents.'));
    }
    return ListView.separated(
      itemCount: documents.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final document = documents[index];
        final extra = document.extra;
        String detail;
        if (document.sourceType == 'loan') {
          detail =
              'Principal ${_m(_num(extra['principal_outstanding']))} • '
              'Interest ${_m(_num(extra['interest_outstanding']))} • '
              'Penalty ${_m(_num(extra['penalty_outstanding']))} • '
              '${_num(extra['interest_rate']).toStringAsFixed(2)}% ${_label(extra['rate_type']?.toString() ?? '')}';
        } else if (document.sourceType == 'purchase_invoice') {
          final supplierInvoice =
              extra['supplier_invoice_number']?.toString() ?? '';
          detail = supplierInvoice.isEmpty
              ? 'Purchasing V2 invoice'
              : 'Supplier invoice: $supplierInvoice';
        } else {
          detail = 'Total ${_m(document.total)} • Paid ${_m(document.paid)}';
        }
        return Card(
          child: ListTile(
            leading: Icon(switch (document.sourceType) {
              'sale' => Icons.receipt_long_outlined,
              'loan' => Icons.account_balance_outlined,
              'purchase' => Icons.shopping_cart_outlined,
              _ => Icons.description_outlined,
            }),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_label(document.sourceType)} • ${document.reference}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  _m(document.balance),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: document.overdue
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(detail),
                  Text(
                    '${document.locationName} • Date ${_d(document.date)} • Due ${_d(document.dueDate)} • ${_label(document.status)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            trailing:
                document.sourceType == 'sale' ||
                    document.sourceType == 'purchase'
                ? OutlinedButton.icon(
                    onPressed: () => _openDocument(document),
                    icon: const Icon(Icons.open_in_new, size: 17),
                    label: const Text('View'),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _payments(List<PartyPaymentActivity> payments) {
    if (payments.isEmpty) {
      return const Center(child: Text('No payment history in this scope.'));
    }
    return ListView.separated(
      itemCount: payments.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final payment = payments[index];
        return ListTile(
          leading: const Icon(Icons.payments_outlined),
          title: Text(
            payment.paymentNumber.isEmpty
                ? _label(payment.paymentType)
                : payment.paymentNumber,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${_d(payment.date)} • ${_label(payment.paymentMethod)}'
            '${payment.reference.isEmpty ? '' : ' • ${payment.reference}'}'
            '${payment.locationName.isEmpty ? '' : ' • ${payment.locationName}'}',
          ),
          trailing: Text(
            _m(payment.amount),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        );
      },
    );
  }

  double _num(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool danger;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              icon,
              color: danger ? Theme.of(context).colorScheme.error : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: danger
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Info extends StatelessWidget {
  final String label;
  final String value;
  const _Info({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 230,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(value.trim().isEmpty ? '—' : value),
      ],
    ),
  );
}
