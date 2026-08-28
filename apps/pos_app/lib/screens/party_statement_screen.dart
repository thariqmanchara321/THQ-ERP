import 'package:flutter/material.dart';
import '../models/client_session.dart';
import '../models/party_statement.dart';
import '../services/party_statement_service.dart';

class PartyStatementScreen extends StatefulWidget {
  final ClientSession session;
  final String partyId;
  final bool customer;
  final String title;
  const PartyStatementScreen({
    super.key,
    required this.session,
    required this.partyId,
    required this.customer,
    required this.title,
  });
  @override
  State<PartyStatementScreen> createState() => _PartyStatementScreenState();
}

class _PartyStatementScreenState extends State<PartyStatementScreen> {
  final _service = PartyStatementService();
  late Future<PartyStatement> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = widget.customer
      ? _service.customerStatement(
          tenantId: widget.session.business.id,
          customerId: widget.partyId,
        )
      : _service.supplierStatement(
          tenantId: widget.session.business.id,
          supplierId: widget.partyId,
        );
  String _m(double v) => widget.session.currencyCode == 'INR'
      ? '₹${v.toStringAsFixed(2)}'
      : '${widget.session.currencyCode} ${v.toStringAsFixed(2)}';
  String _d(DateTime v) =>
      '${v.day.toString().padLeft(2, '0')}-${v.month.toString().padLeft(2, '0')}-${v.year}';
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FA),
    appBar: AppBar(title: Text(widget.title)),
    body: FutureBuilder<PartyStatement>(
      future: _future,
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return Center(
            child: Text(s.error.toString(), textAlign: TextAlign.center),
          );
        }
        final d = s.data!;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.partyName,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Box('Opening', _m(d.openingBalance)),
                  _Box(
                    widget.customer ? 'Invoices' : 'Bills',
                    _m(d.totalDebit),
                  ),
                  _Box('Payments', _m(d.totalCredit)),
                  _Box('Balance', _m(d.closingBalance)),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: d.rows.isEmpty
                      ? const Center(child: Text('No transactions.'))
                      : ListView.separated(
                          itemCount: d.rows.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final r = d.rows[i];
                            return ListTile(
                              title: Text(
                                '${r.reference}  •  ${r.description}',
                              ),
                              subtitle: Text('${_d(r.date)}  •  ${r.type}'),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (r.debit > 0) Text('DR ${_m(r.debit)}'),
                                  if (r.credit > 0) Text('CR ${_m(r.credit)}'),
                                  Text(
                                    'Bal ${_m(r.balance)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
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
        );
      },
    ),
  );
}

class _Box extends StatelessWidget {
  final String l, v;
  const _Box(this.l, this.v);
  @override
  Widget build(BuildContext context) => Container(
    width: 210,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Text(
          v,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}
