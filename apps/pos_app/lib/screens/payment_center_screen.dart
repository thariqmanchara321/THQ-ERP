import 'package:flutter/material.dart';
import '../models/client_session.dart';
import '../models/payment_pending.dart';
import '../services/payment_center_service.dart';
import 'sale_detail_screen.dart';
import 'purchase_detail_screen.dart';

class PaymentCenterScreen extends StatefulWidget {
  final ClientSession session;
  const PaymentCenterScreen({super.key, required this.session});
  @override
  State<PaymentCenterScreen> createState() => _PaymentCenterScreenState();
}

class _PaymentCenterScreenState extends State<PaymentCenterScreen> {
  final _service = PaymentCenterService();
  late Future<PendingPaymentsData> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = _service.load(widget.session.business.id);
  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  String _m(double v) => widget.session.currencyCode == 'INR'
      ? '₹${v.toStringAsFixed(2)}'
      : '${widget.session.currencyCode} ${v.toStringAsFixed(2)}';
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
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
                    'Pending Payments',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Money to receive from customers and money to pay suppliers',
                  ),
                ],
              ),
            ),
            IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: FutureBuilder<PendingPaymentsData>(
            future: _future,
            builder: (context, s) {
              if (s.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.hasError) return Center(child: Text(s.error.toString()));
              final d = s.data!;
              return Row(
                children: [
                  Expanded(
                    child: _Pane(
                      title: 'To Receive',
                      icon: Icons.south_west,
                      amount: d.receivables.fold(0.0, (a, b) => a + b.balance),
                      money: _m,
                      rows: d.receivables,
                      onOpen: (x) => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SaleDetailScreen(
                            session: widget.session,
                            saleId: x.id,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _Pane(
                      title: 'To Pay',
                      icon: Icons.north_east,
                      amount: d.payables.fold(0.0, (a, b) => a + b.balance),
                      money: _m,
                      rows: d.payables,
                      onOpen: (x) => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PurchaseDetailScreen(
                            session: widget.session,
                            purchaseId: x.id,
                          ),
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
  );
}

class _Pane extends StatelessWidget {
  final String title;
  final IconData icon;
  final double amount;
  final String Function(double) money;
  final List<PendingPayment> rows;
  final void Function(PendingPayment) onOpen;
  const _Pane({
    required this.title,
    required this.icon,
    required this.amount,
    required this.money,
    required this.rows,
    required this.onOpen,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                money(amount),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('Nothing pending.'))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, i) {
                      final x = rows[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${x.reference} • ${x.partyName}'),
                        subtitle: Text(
                          x.dueDate == null
                              ? 'No due date'
                              : 'Due ${x.dueDate!.toLocal().toString().split(' ').first}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              money(x.balance),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => onOpen(x),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
