import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pos_models.dart';
import '../models/pos_session.dart';
import '../services/mobile_pos_local_store.dart';

class MobilePosReportScreen extends StatefulWidget {
  final PosSession session;

  const MobilePosReportScreen({super.key, required this.session});

  @override
  State<MobilePosReportScreen> createState() => _MobilePosReportScreenState();
}

class _MobilePosReportScreenState extends State<MobilePosReportScreen> {
  final MobilePosLocalStore _local = MobilePosLocalStore.instance;

  DateTime _day = DateTime.now();
  late Future<_MobilePosReportData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  String get _dayText =>
      '${_day.year.toString().padLeft(4, '0')}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}';

  bool _sameDay(DateTime value, DateTime day) =>
      value.year == day.year &&
      value.month == day.month &&
      value.day == day.day;

  Future<_MobilePosReportData> _load() async {
    await _local.db;
    final localRows = await _local.queue(
      widget.session.tenantId,
      widget.session.deviceId,
      limit: 1000,
    );
    final localForDay = localRows.where((row) => _sameDay(row.createdAt.toLocal(), _day)).toList();

    Map<String, dynamic> summary = const {};
    Map<String, dynamic> detail = const {};
    String? onlineError;

    try {
      final raw = await Supabase.instance.client.rpc(
        'pos_terminal_day_v473',
        params: {
          'p_tenant_id': widget.session.tenantId,
          'p_device_id': widget.session.deviceId,
          'p_day': _dayText,
        },
      );
      if (raw is Map) summary = Map<String, dynamic>.from(raw);
    } catch (error) {
      try {
        final raw = await Supabase.instance.client.rpc(
          'pos_terminal_day_v471',
          params: {
            'p_tenant_id': widget.session.tenantId,
            'p_device_id': widget.session.deviceId,
            'p_day': _dayText,
          },
        );
        if (raw is Map) summary = Map<String, dynamic>.from(raw);
      } catch (fallbackError) {
        onlineError = fallbackError.toString();
      }
    }

    // v4.7.3 intentionally keeps Terminal Daily summary-only. Fetch the mature
    // v4.7.1 detail payload separately for invoice drill-down when available.
    try {
      final raw = await Supabase.instance.client.rpc(
        'pos_terminal_day_v471',
        params: {
          'p_tenant_id': widget.session.tenantId,
          'p_device_id': widget.session.deviceId,
          'p_day': _dayText,
        },
      );
      if (raw is Map) detail = Map<String, dynamic>.from(raw);
    } catch (_) {}

    return _MobilePosReportData(
      summary: summary,
      detail: detail,
      localRows: localForDay,
      onlineError: onlineError,
    );
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _day = picked;
      _future = _load();
    });
  }

  String _money(dynamic value) {
    final amount = numberValue(value);
    return '${widget.session.currencyCode} ${amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Reports',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Choose date',
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: 'Refresh report',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_MobilePosReportData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(snapshot.error.toString()),
              ),
            );
          }

          final data = snapshot.data!;
          final summary = data.summary;
          final detail = data.detail;
          final invoices = (detail['invoices'] as List? ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          final localNotSynced = data.localRows
              .where(
                (row) =>
                    row.status != 'synced' && row.status != 'cancelled',
              )
              .length;
          final localSynced =
              data.localRows.where((row) => row.status == 'synced').length;

          final serverAvailable = summary.isNotEmpty;
          final localTotal = data.localRows.fold<double>(
            0,
            (sum, row) => sum + numberValue(row.payload['total']),
          );
          final grossSales = serverAvailable
              ? numberValue(summary['gross_sales'])
              : localTotal;
          final invoiceCount = serverAvailable
              ? numberValue(summary['invoice_count']).toInt()
              : data.localRows.length;
          final salesReturns = numberValue(summary['sales_returns']);
          final netSales = summary.containsKey('net_sales')
              ? numberValue(summary['net_sales'])
              : (grossSales - salesReturns).clamp(0, double.infinity);
          final expenses = numberValue(summary['expenses']);
          final purchases = numberValue(summary['purchases']);
          final collected = summary.containsKey('total_collected')
              ? numberValue(summary['total_collected'])
              : numberValue(summary['cash']) +
                  numberValue(summary['upi']) +
                  numberValue(summary['card']) +
                  numberValue(summary['bank']) +
                  numberValue(summary['other_payments']);

          return RefreshIndicator(
            onRefresh: () async {
              final next = _load();
              setState(() => _future = next);
              await next;
            },
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _dateHeader(serverAvailable, data.onlineError),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 900
                        ? 4
                        : constraints.maxWidth >= 600
                            ? 3
                            : 2;
                    final cards = <Widget>[
                      _metric(
                        'Gross sales',
                        _money(grossSales),
                        Icons.point_of_sale_outlined,
                      ),
                      _metric(
                        'Net sales',
                        _money(netSales),
                        Icons.trending_up_rounded,
                      ),
                      _metric(
                        'Transactions',
                        '$invoiceCount',
                        Icons.receipt_long_outlined,
                      ),
                      _metric(
                        'Collected',
                        _money(collected),
                        Icons.payments_outlined,
                      ),
                      _metric(
                        'Sales returns',
                        _money(salesReturns),
                        Icons.assignment_return_outlined,
                      ),
                      _metric(
                        'Expenses',
                        _money(expenses),
                        Icons.account_balance_wallet_outlined,
                      ),
                      if (summary.containsKey('purchases'))
                        _metric(
                          'Purchases',
                          _money(purchases),
                          Icons.shopping_bag_outlined,
                        ),
                      _metric(
                        'Not synced',
                        '$localNotSynced',
                        Icons.cloud_upload_outlined,
                      ),
                    ];
                    return GridView.count(
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      crossAxisCount: columns,
                      childAspectRatio: 2.2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      children: cards,
                    );
                  },
                ),
                const SizedBox(height: 10),
                _section(
                  title: 'Payment collection',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _paymentChip('Cash', summary['cash']),
                      _paymentChip('UPI', summary['upi']),
                      _paymentChip('Card', summary['card']),
                      _paymentChip('Bank', summary['bank']),
                      _paymentChip('Other', summary['other_payments']),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _section(
                  title: 'Offline / sync status',
                  child: Row(
                    children: [
                      Expanded(
                        child: _smallStatus(
                          'Synced',
                          localSynced,
                          Icons.cloud_done_outlined,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _smallStatus(
                          'Not synced',
                          localNotSynced,
                          Icons.cloud_upload_outlined,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _smallStatus(
                          'Local records',
                          data.localRows.length,
                          Icons.storage_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _section(
                  title: 'Transactions',
                  child: invoices.isNotEmpty
                      ? Column(
                          children: [
                            for (final invoice in invoices.take(100))
                              _serverInvoiceRow(invoice),
                          ],
                        )
                      : data.localRows.isNotEmpty
                          ? Column(
                              children: [
                                for (final invoice in data.localRows.take(100))
                                  _localInvoiceRow(invoice),
                              ],
                            )
                          : const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text('No transactions for this date.'),
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

  Widget _dateHeader(bool serverAvailable, String? error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE5EE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today_outlined, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dayText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                Text(
                  serverAvailable
                      ? 'Server report + local sync status'
                      : 'Offline/local report${error == null ? '' : ' • server unavailable'}',
                  style: const TextStyle(
                    color: Color(0xFF758296),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _pickDay,
            icon: const Icon(Icons.edit_calendar_outlined, size: 17),
            label: const Text('Date'),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE4EAF1)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF147AF3), size: 19),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7A8798),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF14233B),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE5EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF14233B),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _paymentChip(String label, dynamic raw) {
    return Container(
      constraints: const BoxConstraints(minWidth: 115),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F9FC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7A8798),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            _money(raw),
            style: const TextStyle(
              color: Color(0xFF14233B),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallStatus(String label, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F9FC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: const Color(0xFF147AF3)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '$label\n$value',
              maxLines: 2,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _serverInvoiceRow(Map<String, dynamic> row) {
    final number = row['invoice_number']?.toString() ??
        row['sale_number']?.toString() ??
        'Invoice';
    final customer = row['customer_name']?.toString() ?? 'Walk-in Customer';
    final total = row['grand_total'];
    return _transactionRow(
      icon: Icons.receipt_long_outlined,
      title: number,
      subtitle: customer,
      amount: _money(total),
      status: row['status']?.toString() ?? 'posted',
    );
  }

  Widget _localInvoiceRow(LocalInvoice row) {
    return _transactionRow(
      icon: row.status == 'synced'
          ? Icons.cloud_done_outlined
          : Icons.cloud_upload_outlined,
      title: row.serverResponse?['sale_number']?.toString() ?? row.localNumber,
      subtitle: row.payload['customer_name']?.toString() ?? 'Walk-in Customer',
      amount: _money(row.payload['total']),
      status: row.status,
    );
  }

  Widget _transactionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required String amount,
    required String status,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEDF1F5))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF60748A)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7A8798),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5FA),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status.toUpperCase(),
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePosReportData {
  final Map<String, dynamic> summary;
  final Map<String, dynamic> detail;
  final List<LocalInvoice> localRows;
  final String? onlineError;

  const _MobilePosReportData({
    required this.summary,
    required this.detail,
    required this.localRows,
    required this.onlineError,
  });
}
