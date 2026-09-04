import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MultiPaymentEditor extends StatefulWidget {
  const MultiPaymentEditor({
    super.key,
    required this.tenantId,
    required this.total,
    required this.customerIsWalkIn,
    required this.customerName,
    required this.onChanged,
    this.initialAllocations = const [],
    this.enabled = true,
  });

  final String tenantId;
  final double total;
  final bool customerIsWalkIn;
  final String customerName;
  final List<Map<String, dynamic>> initialAllocations;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool enabled;

  @override
  State<MultiPaymentEditor> createState() => _MultiPaymentEditorState();
}

class _Method {
  const _Method({required this.code, required this.name, required this.mapped});

  final String code;
  final String name;
  final bool mapped;

  factory _Method.fromMap(Map<String, dynamic> row) => _Method(
    code: row['code']?.toString() ?? '',
    name: row['display_name']?.toString() ?? '',
    mapped:
        row['code']?.toString() == 'credit' || row['ledger_account_id'] != null,
  );
}

class _MethodCacheEntry {
  const _MethodCacheEntry({required this.loadedAt, required this.methods});

  final DateTime loadedAt;
  final List<_Method> methods;
}

class _Row {
  _Row({required this.method, double amount = 0, String reference = ''})
    : amount = TextEditingController(
        text: amount <= 0 ? '' : amount.toStringAsFixed(2),
      ),
      reference = TextEditingController(text: reference);

  String method;
  final TextEditingController amount;
  final TextEditingController reference;

  void dispose() {
    amount.dispose();
    reference.dispose();
  }
}

class _MultiPaymentEditorState extends State<MultiPaymentEditor> {
  static const Duration _methodCacheTtl = Duration(minutes: 2);
  static final Map<String, _MethodCacheEntry> _methodCache =
      <String, _MethodCacheEntry>{};

  bool _loading = true;
  String? _error;
  List<_Method> _methods = const [];
  final List<_Row> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<List<_Method>> _methodsForTenant() async {
    final now = DateTime.now();
    final cached = _methodCache[widget.tenantId];
    if (cached != null && now.difference(cached.loadedAt) < _methodCacheTtl) {
      return cached.methods;
    }

    final raw = await Supabase.instance.client.rpc(
      'payment_methods_list_v522',
      params: {'p_tenant_id': widget.tenantId},
    );
    final methods = List<_Method>.unmodifiable(
      (raw as List? ?? const []).whereType<Map>().map(
        (row) => _Method.fromMap(Map<String, dynamic>.from(row)),
      ),
    );
    _methodCache[widget.tenantId] = _MethodCacheEntry(
      loadedAt: now,
      methods: methods,
    );
    return methods;
  }

  Future<void> _load() async {
    try {
      final methods = await _methodsForTenant();

      if (!mounted) return;
      setState(() {
        _methods = methods;
        final supported = methods.map((e) => e.code).toSet();
        for (final item in widget.initialAllocations) {
          final code = item['method_code']?.toString() ?? '';
          if (!supported.contains(code)) continue;
          _rows.add(
            _Row(
              method: code,
              amount:
                  (item['tendered_amount'] as num?)?.toDouble() ??
                  double.tryParse('${item['tendered_amount']}') ??
                  0,
              reference: item['reference_number']?.toString() ?? '',
            ),
          );
        }
        if (_rows.isEmpty && methods.isNotEmpty) {
          final cash = methods.where((e) => e.code == 'cash').firstOrNull;
          _rows.add(
            _Row(method: (cash ?? methods.first).code, amount: widget.total),
          );
        }
        _loading = false;
      });
      _emit();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  double _number(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  List<Map<String, dynamic>> _value() => _rows
      .where((row) => _number(row.amount) > 0)
      .map(
        (row) => <String, dynamic>{
          'method_code': row.method,
          'tendered_amount': _number(row.amount),
          'reference_number': row.reference.text.trim(),
        },
      )
      .toList(growable: false);

  void _emit() => widget.onChanged(_value());

  double get _remaining {
    var remaining = widget.total;
    for (final row in _rows) {
      final amount = _number(row.amount).clamp(0.0, double.infinity);
      final used = amount > remaining ? remaining : amount;
      remaining = (remaining - used).clamp(0.0, widget.total).toDouble();
    }
    return remaining;
  }

  double get _change {
    var remaining = widget.total;
    var change = 0.0;
    for (final row in _rows) {
      final amount = _number(row.amount).clamp(0.0, double.infinity);
      final used = amount > remaining ? remaining : amount;
      if (row.method == 'cash' && amount > used) {
        change += amount - used;
      }
      remaining = (remaining - used).clamp(0.0, widget.total).toDouble();
    }
    return change;
  }

  void _add() {
    if (_methods.isEmpty) return;
    final used = _rows.map((e) => e.method).toSet();
    final unused = _methods.where((m) => !used.contains(m.code)).toList();
    final method = unused.isEmpty ? _methods.first : unused.first;
    setState(() => _rows.add(_Row(method: method.code, amount: _remaining)));
    _emit();
  }

  void _remove(int index) {
    final row = _rows.removeAt(index);
    row.dispose();
    setState(() {});
    _emit();
  }

  void _fill(_Row row) {
    var other = 0.0;
    for (final current in _rows) {
      if (identical(current, row)) continue;
      other += _number(current.amount);
    }
    final balance = (widget.total - other).clamp(0.0, widget.total);
    setState(() => row.amount.text = balance.toStringAsFixed(2));
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LinearProgressIndicator();
    if (_error != null) {
      return Text(
        'Payment methods unavailable: $_error',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Payment Allocations',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: widget.enabled ? _add : null,
              icon: const Icon(Icons.add),
              label: const Text('Add Method'),
            ),
          ],
        ),
        for (var i = 0; i < _rows.length; i++) ...[
          _paymentRow(i),
          if (i + 1 < _rows.length) const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Text('Invoice ${widget.total.toStringAsFixed(2)}'),
            Text(
              'Remaining ${_remaining.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _remaining > .005
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
            if (_change > .005)
              Text(
                'Cash change ${_change.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
          ],
        ),
        const SizedBox(height: 5),
        const Text(
          'Cash over-tender becomes change. Electronic overpayment is rejected. '
          'Credit stays in Accounts Receivable and requires a named customer.',
          style: TextStyle(fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _paymentRow(int index) {
    final row = _rows[index];
    final creditBlocked = row.method == 'credit' && widget.customerIsWalkIn;
    return LayoutBuilder(
      builder: (context, constraints) {
        final method = DropdownButtonFormField<String>(
          initialValue: row.method,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Method',
            border: OutlineInputBorder(),
          ),
          items: _methods
              .map(
                (m) => DropdownMenuItem(
                  value: m.code,
                  enabled: m.mapped,
                  child: Text(
                    m.mapped ? m.name : '${m.name} • map ledger first',
                  ),
                ),
              )
              .toList(),
          onChanged: !widget.enabled
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => row.method = value);
                  _emit();
                },
        );

        final amount = TextField(
          controller: row.amount,
          enabled: widget.enabled && !creditBlocked,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) {
            setState(() {});
            _emit();
          },
          decoration: InputDecoration(
            labelText: creditBlocked
                ? 'Named customer required'
                : 'Amount / Tendered',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Use balance',
              onPressed: widget.enabled && !creditBlocked
                  ? () => _fill(row)
                  : null,
              icon: const Icon(Icons.done_all),
            ),
          ),
        );

        final reference = TextField(
          controller: row.reference,
          enabled: widget.enabled && row.method != 'credit',
          onChanged: (_) => _emit(),
          decoration: const InputDecoration(
            labelText: 'Reference',
            border: OutlineInputBorder(),
          ),
        );

        final remove = IconButton(
          tooltip: 'Remove',
          onPressed: widget.enabled && _rows.length > 1
              ? () => _remove(index)
              : null,
          icon: const Icon(Icons.delete_outline),
        );

        if (constraints.maxWidth < 520) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: method),
                  remove,
                ],
              ),
              const SizedBox(height: 8),
              amount,
              const SizedBox(height: 8),
              reference,
            ],
          );
        }

        return Row(
          children: [
            Expanded(flex: 2, child: method),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: amount),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: reference),
            remove,
          ],
        );
      },
    );
  }
}
