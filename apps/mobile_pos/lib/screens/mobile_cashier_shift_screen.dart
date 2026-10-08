import 'package:flutter/material.dart';

import '../models/pos_models.dart';
import '../models/pos_session.dart';
import '../services/mobile_cashier_shift_service.dart';

class MobileCashierShiftScreen extends StatefulWidget {
  final PosSession session;

  const MobileCashierShiftScreen({super.key, required this.session});

  @override
  State<MobileCashierShiftScreen> createState() =>
      _MobileCashierShiftScreenState();
}

class _MobileCashierShiftScreenState extends State<MobileCashierShiftScreen> {
  final _service = MobileCashierShiftService();
  final _openingCash = TextEditingController(text: '0');
  final _declaredCash = TextEditingController(text: '0');
  final _note = TextEditingController();

  late Future<Map<String, dynamic>> _future;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _service.current(widget.session);
  }

  @override
  void dispose() {
    _openingCash.dispose();
    _declaredCash.dispose();
    _note.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _error = null;
      _future = _service.current(widget.session);
    });
  }

  String _money(dynamic value) =>
      '${widget.session.currencyCode} ${numberValue(value).toStringAsFixed(2)}';

  Future<void> _openShift() async {
    final amount = double.tryParse(_openingCash.text.trim()) ?? -1;
    if (amount < 0) {
      setState(() => _error = 'Opening cash cannot be negative.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.open(
        widget.session,
        openingCash: amount,
        note: _note.text.trim(),
      );
      if (!mounted) return;
      _note.clear();
      _reload();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cashier shift opened.')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeShift(Map<String, dynamic> shift) async {
    final amount = double.tryParse(_declaredCash.text.trim()) ?? -1;
    if (amount < 0) {
      setState(() => _error = 'Declared cash cannot be negative.');
      return;
    }
    final id = shift['id']?.toString() ?? shift['shift_id']?.toString() ?? '';
    if (id.isEmpty) {
      setState(
        () => _error = 'Open shift identity is missing. Refresh and retry.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.close(
        widget.session,
        shiftId: id,
        declaredCash: amount,
        note: _note.text.trim(),
      );
      if (!mounted) return;
      _note.clear();
      _openingCash.text = '0';
      _declaredCash.text = '0';
      _reload();
      final diff = _money(result['difference']);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Shift closed. Cash difference: $diff')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cashier Shift'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _bodyError(snapshot.error.toString());
          }
          final shift = snapshot.data ?? const <String, dynamic>{};
          final hasOpenShift =
              (shift['id']?.toString() ?? shift['shift_id']?.toString() ?? '')
                  .isNotEmpty;
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _terminalCard(),
              const SizedBox(height: 12),
              if (_error != null) ...[
                _message(_error!, error: true),
                const SizedBox(height: 12),
              ],
              if (hasOpenShift) _openShiftCard(shift) else _startShiftCard(),
            ],
          );
        },
      ),
    );
  }

  Widget _terminalCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.session.locationName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 3),
          Text(
            '${widget.session.deviceName} • ${widget.session.deviceCode}\n${widget.session.username}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  Widget _startShiftCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Start shift', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Opening a shift uses the existing terminal/location permission checks.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _openingCash,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Opening cash',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Opening note (optional)',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _openShift,
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: Text(_busy ? 'Opening…' : 'Open shift'),
          ),
        ],
      ),
    ),
  );

  Widget _openShiftCard(Map<String, dynamic> shift) {
    final expected = numberValue(shift['expected_cash_now']);
    if (_declaredCash.text == '0' && expected > 0) {
      _declaredCash.text = expected.toStringAsFixed(2);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shift['shift_number']?.toString() ?? 'Open shift',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Cashier: ${shift['cashier_name'] ?? widget.session.username}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Chip(label: Text('OPEN')),
              ],
            ),
            const SizedBox(height: 12),
            _metric('Opening cash', shift['opening_cash']),
            _metric('Cash sales', shift['cash_sales']),
            _metric('Customer receipts', shift['customer_receipts']),
            _metric('Cash in', shift['cash_in']),
            _metric('Cash out', shift['cash_out']),
            _metric('Cash expenses', shift['cash_expenses']),
            _metric('Refunds', shift['refunds']),
            const Divider(height: 24),
            _metric(
              'Expected cash now',
              shift['expected_cash_now'],
              strong: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _declaredCash,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Declared cash at close',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Closing note (optional)',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : () => _closeShift(shift),
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(_busy ? 'Closing…' : 'Close shift'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, dynamic value, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          _money(value),
          style: TextStyle(
            fontWeight: strong ? FontWeight.w600 : FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _message(String text, {bool error = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? scheme.errorContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: error ? scheme.onErrorContainer : scheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _bodyError(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}
