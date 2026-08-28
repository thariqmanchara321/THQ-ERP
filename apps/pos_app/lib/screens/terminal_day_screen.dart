import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/client_session.dart';
import '../services/terminal_day_export_service.dart';
import '../services/terminal_day_service.dart';
import 'sale_detail_screen.dart';

class TerminalDayScreen extends StatefulWidget {
  final ClientSession session;

  const TerminalDayScreen({super.key, required this.session});

  @override
  State<TerminalDayScreen> createState() => _TerminalDayScreenState();
}

class _TerminalDayScreenState extends State<TerminalDayScreen> {
  final TerminalDayService _service = TerminalDayService();
  final TerminalDayExportService _exportService = TerminalDayExportService();
  final TextEditingController _invoiceSearch = TextEditingController();

  DateTime _day = DateTime.now();
  bool _loading = true;
  bool _exporting = false;
  bool _showInvoices = false;
  bool _invoiceLoading = false;
  String? _error;
  String? _invoiceError;
  Map<String, dynamic> _data = const {};
  List<Map<String, dynamic>> _invoices = const [];
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _invoiceSearch.dispose();
    super.dispose();
  }

  double _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0.0;

  String _money(dynamic value) {
    final prefix = widget.session.currencyCode == 'INR'
        ? '₹'
        : '${widget.session.currencyCode} ';
    return '$prefix${_number(value).toStringAsFixed(2)}';
  }

  String _date(DateTime value) => DateFormat('dd MMM yyyy').format(value);

  String _dateTime(dynamic value) {
    if (value == null) return '-';
    final parsed = DateTime.tryParse(value.toString())?.toLocal();
    if (parsed == null) return '-';
    return DateFormat('dd MMM • hh:mm a').format(parsed);
  }

  bool get _isToday {
    final now = DateTime.now();
    return _day.year == now.year &&
        _day.month == now.month &&
        _day.day == now.day;
  }

  Future<void> _load() async {
    final deviceId = widget.session.device?.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This POS terminal is not activated.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.load(
        tenantId: widget.session.business.id,
        deviceId: deviceId,
        day: _day,
      );
      if (!mounted) return;
      setState(() => _data = data);
      if (_showInvoices) await _loadInvoices();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadInvoices() async {
    final deviceId = widget.session.device?.deviceId;
    if (deviceId == null || deviceId.isEmpty) return;
    setState(() {
      _invoiceLoading = true;
      _invoiceError = null;
    });
    try {
      final rows = await _service.searchInvoices(
        tenantId: widget.session.business.id,
        deviceId: deviceId,
        day: _day,
        query: _invoiceSearch.text,
      );
      if (mounted) setState(() => _invoices = rows);
    } catch (error) {
      if (mounted) setState(() => _invoiceError = error.toString());
    } finally {
      if (mounted) setState(() => _invoiceLoading = false);
    }
  }

  void _searchChanged(String _) {
    if (mounted) setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), _loadInvoices);
  }

  Future<void> _toggleInvoices() async {
    if (_showInvoices) {
      setState(() => _showInvoices = false);
      return;
    }
    setState(() => _showInvoices = true);
    await _loadInvoices();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDate: _day.isAfter(now) ? now : _day,
    );
    if (picked == null) return;
    setState(() {
      _day = picked;
      _invoiceSearch.clear();
      _invoices = const [];
    });
    await _load();
  }

  Future<void> _moveDay(int delta) async {
    final target = DateTime(_day.year, _day.month, _day.day + delta);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (target.isAfter(today)) return;
    setState(() {
      _day = target;
      _invoiceSearch.clear();
      _invoices = const [];
    });
    await _load();
  }

  Future<void> _openInvoice(Map<String, dynamic> row) async {
    final id = row['sale_id']?.toString() ?? '';
    if (id.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SaleDetailScreen(session: widget.session, saleId: id),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _export(String format) async {
    if (_exporting || _data.isEmpty) return;
    setState(() => _exporting = true);
    final terminalLabel =
        '${widget.session.device?.locationCode ?? ''} • ${widget.session.device?.deviceCode ?? ''}';
    try {
      if (format == 'pdf') {
        await _exportService.savePdf(
          businessName: widget.session.business.name,
          terminalLabel: terminalLabel,
          day: _day,
          currency: widget.session.currencyCode,
          data: _data,
        );
      } else if (format == 'xlsx') {
        await _exportService.saveExcel(
          businessName: widget.session.business.name,
          terminalLabel: terminalLabel,
          day: _day,
          data: _data,
        );
      } else {
        await _exportService.printReport(
          businessName: widget.session.business.name,
          terminalLabel: terminalLabel,
          day: _day,
          currency: widget.session.currencyCode,
          data: _data,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              format == 'print'
                  ? 'Print dialog opened.'
                  : '${format.toUpperCase()} daily report created.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shifts = _data['shift_summary'] is Map
        ? Map<String, dynamic>.from(_data['shift_summary'] as Map)
        : <String, dynamic>{};

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              _header(),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _errorCard()
              else ...[
                _headlineSummary(),
                const SizedBox(height: 12),
                _paymentSummary(),
                const SizedBox(height: 12),
                _activitySummary(),
                const SizedBox(height: 12),
                _shiftSummary(shifts),
                const SizedBox(height: 12),
                _invoiceSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Terminal Daily',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            const Text(
              'Simple read-only summary for this POS. Choose any day, then drill into invoices only when needed.',
            ),
            const SizedBox(height: 3),
            Text(
              '${widget.session.device?.locationCode ?? ''} • ${widget.session.device?.deviceCode ?? ''}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 7,
          runSpacing: 7,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton.filledTonal(
              onPressed: _loading ? null : () => _moveDay(-1),
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous day',
            ),
            OutlinedButton.icon(
              onPressed: _pickDay,
              icon: const Icon(Icons.calendar_today_outlined, size: 17),
              label: Text(_date(_day)),
            ),
            IconButton.filledTonal(
              onPressed: _loading || _isToday ? null : () => _moveDay(1),
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next day',
            ),
            OutlinedButton.icon(
              onPressed: _exporting || _loading ? null : () => _export('pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
              label: const Text('PDF'),
            ),
            OutlinedButton.icon(
              onPressed: _exporting || _loading ? null : () => _export('xlsx'),
              icon: const Icon(Icons.table_view_outlined, size: 17),
              label: const Text('Excel'),
            ),
            OutlinedButton.icon(
              onPressed: _exporting || _loading ? null : () => _export('print'),
              icon: const Icon(Icons.print_outlined, size: 17),
              label: const Text('Print'),
            ),
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
        );
        if (constraints.maxWidth < 920) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 12), actions],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            actions,
          ],
        );
      },
    );
  }

  Widget _errorCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );

  Widget _headlineSummary() => _section(
        title: 'Daily Summary',
        icon: Icons.summarize_outlined,
        children: [
          _metric('Invoices', '${_data['invoice_count'] ?? 0}', Icons.receipt_long_outlined),
          _metric('Gross Sales', _money(_data['gross_sales']), Icons.trending_up),
          _metric('Sales Returns', _money(_data['sales_returns']), Icons.keyboard_return_outlined),
          _metric('Net Sales', _money(_data['net_sales']), Icons.account_balance_wallet_outlined),
          _metric('Collected', _money(_data['total_collected']), Icons.savings_outlined),
          _metric('Outstanding', _money(_data['sales_outstanding']), Icons.pending_actions_outlined),
        ],
      );

  Widget _paymentSummary() => _section(
        title: 'Payments',
        icon: Icons.payments_outlined,
        children: [
          _metric('Cash', _money(_data['cash']), Icons.payments_outlined),
          _metric('UPI', _money(_data['upi']), Icons.qr_code_2_outlined),
          _metric('Card', _money(_data['card']), Icons.credit_card_outlined),
          _metric('Bank', _money(_data['bank']), Icons.account_balance_outlined),
          _metric('Other', _money(_data['other_payments']), Icons.more_horiz),
          _metric('Customer Receipts', _money(_data['customer_receipts']), Icons.person_outline),
        ],
      );

  Widget _activitySummary() => _section(
        title: 'Other Activity',
        icon: Icons.fact_check_outlined,
        children: [
          _metric('Discount', _money(_data['sales_discount']), Icons.percent_outlined),
          _metric('Tax', _money(_data['sales_tax']), Icons.receipt_outlined),
          _metric('Expenses', _money(_data['expenses']), Icons.money_off_outlined),
          _metric('Purchases', _money(_data['purchases']), Icons.shopping_cart_outlined),
          _metric('Purchase Returns', _money(_data['purchase_returns']), Icons.assignment_return_outlined),
          _metric('Cash In', _money(_data['cash_in']), Icons.add_circle_outline),
          _metric('Cash Out', _money(_data['cash_out']), Icons.remove_circle_outline),
          if (_isToday)
            _metric('Held Now', '${_data['held_count'] ?? 0}', Icons.pause_circle_outline),
        ],
      );

  Widget _shiftSummary(Map<String, dynamic> shifts) => _section(
        title: 'Cashier Shift Summary',
        icon: Icons.badge_outlined,
        subtitle: 'Reporting only. Shift start/end and cash are managed from Cashier Shift.',
        children: [
          _metric('Shifts', '${shifts['shift_count'] ?? 0}', Icons.badge_outlined),
          _metric('First Start', _dateTime(shifts['first_start']), Icons.login),
          _metric('Last End', _dateTime(shifts['last_end']), Icons.logout),
          _metric('Opening Cash', _money(shifts['opening_cash']), Icons.account_balance_wallet_outlined),
          _metric('Closing Cash', _money(shifts['closing_cash']), Icons.wallet_outlined),
          _metric('Difference', _money(shifts['difference']), Icons.balance_outlined),
        ],
      );

  Widget _invoiceSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Invoices',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'Search invoices from ${_date(_day)} on this POS only.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _toggleInvoices,
                  icon: Icon(_showInvoices ? Icons.expand_less : Icons.search),
                  label: Text(_showInvoices ? 'Hide Invoices' : 'View Invoices'),
                ),
              ],
            ),
            if (_showInvoices) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _invoiceSearch,
                onChanged: _searchChanged,
                onSubmitted: (_) => _loadInvoices(),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Invoice number / sale number / customer…',
                  suffixIcon: _invoiceSearch.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            _invoiceSearch.clear();
                            _loadInvoices();
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              if (_invoiceLoading)
                const LinearProgressIndicator()
              else if (_invoiceError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_invoiceError!, textAlign: TextAlign.center),
                )
              else if (_invoices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No matching invoices for this day.')),
                )
              else
                ..._invoices.map(_invoiceTile),
            ],
          ],
        ),
      ),
    );
  }

  Widget _invoiceTile(Map<String, dynamic> row) {
    final invoice = row['invoice_number']?.toString() ??
        row['sale_number']?.toString() ??
        '';
    final customer = row['customer_name']?.toString() ?? '';
    final created = DateTime.tryParse('${row['created_at']}')?.toLocal();
    final time = created == null ? '' : DateFormat('hh:mm a').format(created);
    final balance = _number(row['outstanding_amount']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onTap: () => _openInvoice(row),
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(
            '$invoice${customer.isEmpty ? '' : ' • $customer'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            [
              if (time.isNotEmpty) time,
              'Paid ${_money(row['paid_amount'])}',
              if (_number(row['returned_amount']) > 0)
                'Returned ${_money(row['returned_amount'])}',
              if (balance > 0) 'Balance ${_money(balance)}',
            ].join(' • '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            _money(row['grand_total']),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: children),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon) {
    return SizedBox(
      width: 190,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18),
              const SizedBox(height: 9),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
