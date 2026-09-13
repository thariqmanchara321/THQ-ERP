import 'package:flutter/material.dart';

class MobilePaymentLine {
  final String name;
  final String sku;
  final double quantity;
  final String unitCode;
  final double unitPrice;
  final double taxRate;

  const MobilePaymentLine({
    required this.name,
    required this.sku,
    required this.quantity,
    required this.unitCode,
    required this.unitPrice,
    required this.taxRate,
  });

  double get gross => quantity * unitPrice;
}

class MobilePaymentAllocation {
  final String methodCode;
  final double amount;
  final String reference;

  const MobilePaymentAllocation({
    required this.methodCode,
    required this.amount,
    this.reference = '',
  });

  Map<String, dynamic> toMap() => <String, dynamic>{
        'method_code': methodCode,
        'tendered_amount': amount,
        'reference_number': reference.trim().isEmpty ? null : reference.trim(),
      };
}

class MobilePaymentResult {
  final double discountAmount;
  final double roundOff;
  final double subtotal;
  final double tax;
  final double total;
  final double cashReceived;
  final List<MobilePaymentAllocation> allocations;
  final String notes;

  const MobilePaymentResult({
    required this.discountAmount,
    required this.roundOff,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.cashReceived,
    required this.allocations,
    required this.notes,
  });

  double get paidAmount => allocations
      .where((allocation) => allocation.methodCode != 'credit')
      .fold<double>(0, (sum, allocation) => sum + allocation.amount);

  String get primaryMethod =>
      allocations.isEmpty ? 'cash' : allocations.first.methodCode;

  String get primaryReference =>
      allocations.isEmpty ? '' : allocations.first.reference;
}

class MobilePosPaymentScreen extends StatefulWidget {
  final String currencyCode;
  final String customerName;
  final bool allowCredit;
  final List<MobilePaymentLine> lines;
  final double initialRoundOff;

  const MobilePosPaymentScreen({
    super.key,
    required this.currencyCode,
    required this.customerName,
    required this.allowCredit,
    required this.lines,
    this.initialRoundOff = 0,
  });

  @override
  State<MobilePosPaymentScreen> createState() =>
      _MobilePosPaymentScreenState();
}

class _MobilePosPaymentScreenState extends State<MobilePosPaymentScreen> {
  static const _accent = Color(0xFF147AF3);
  static const _success = Color(0xFF14A765);
  static const _ink = Color(0xFF152238);
  static const _muted = Color(0xFF6E7C91);
  static const _line = Color(0xFFE6EBF2);
  static const _surface = Color(0xFFF6F8FB);

  final _discount = TextEditingController(text: '0');
  final _roundOff = TextEditingController(text: '0.00');
  final _received = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();

  String _discountMode = 'amount';
  String _method = 'cash';
  final List<_SplitDraft> _split = <_SplitDraft>[];

  @override
  void initState() {
    super.initState();
    _roundOff.text = widget.initialRoundOff.toStringAsFixed(2);
    _received.text = _total.toStringAsFixed(2);
    _discount.addListener(_recalculate);
    _roundOff.addListener(_recalculate);
  }

  @override
  void dispose() {
    _discount.removeListener(_recalculate);
    _roundOff.removeListener(_recalculate);
    _discount.dispose();
    _roundOff.dispose();
    _received.dispose();
    _reference.dispose();
    _notes.dispose();
    for (final row in _split) {
      row.dispose();
    }
    super.dispose();
  }

  void _recalculate() {
    if (!mounted) return;
    setState(() {});
  }

  double get _subtotal =>
      widget.lines.fold<double>(0, (sum, line) => sum + line.gross);

  double get _discountValue {
    final raw = double.tryParse(_discount.text.trim()) ?? 0;
    if (_discountMode == 'percent') {
      return (_subtotal * raw.clamp(0, 100) / 100)
          .clamp(0, _subtotal)
          .toDouble();
    }
    return raw.clamp(0, _subtotal).toDouble();
  }

  double get _tax {
    if (_subtotal <= 0) return 0;
    var result = 0.0;
    for (final line in widget.lines) {
      final allocatedDiscount = _discountValue * (line.gross / _subtotal);
      final taxable = (line.gross - allocatedDiscount).clamp(0, line.gross);
      result += taxable * line.taxRate / 100;
    }
    return result;
  }

  double get _roundOffValue => double.tryParse(_roundOff.text.trim()) ?? 0;

  double get _beforeRoundOff => _subtotal - _discountValue + _tax;

  double get _total => (_beforeRoundOff + _roundOffValue)
      .clamp(0, double.infinity)
      .toDouble();

  double get _receivedValue => double.tryParse(_received.text.trim()) ?? 0;

  double get _change => _method == 'cash'
      ? (_receivedValue - _total).clamp(0, double.infinity).toDouble()
      : 0;

  String _money(double value) =>
      '${widget.currencyCode} ${value.toStringAsFixed(2)}';

  void _setMethod(String value) {
    if (value == 'credit' && !widget.allowCredit) {
      _show('Walk-in customer cannot use credit.');
      return;
    }
    setState(() {
      _method = value;
      if (value == 'split') {
        if (_split.isEmpty) {
          _split.add(_SplitDraft(method: 'cash', amount: _total));
        }
      } else if (value != 'credit') {
        _received.text = _total.toStringAsFixed(2);
      }
    });
  }

  void _autoRound() {
    final delta = _beforeRoundOff.roundToDouble() - _beforeRoundOff;
    _roundOff.text =
        delta.abs() < 0.000001 ? '0.00' : delta.toStringAsFixed(2);
  }

  void _addSplit() {
    setState(() {
      final allocated = _split.fold<double>(0, (sum, row) => sum + row.amount);
      final balance = (_total - allocated).clamp(0, double.infinity).toDouble();
      _split.add(_SplitDraft(method: 'card', amount: balance));
    });
  }

  void _removeSplit(int index) {
    final row = _split.removeAt(index);
    row.dispose();
    setState(() {});
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _complete() {
    if (_total <= 0) {
      _show('Payment total must be greater than zero.');
      return;
    }

    final allocations = <MobilePaymentAllocation>[];
    var cashReceived = 0.0;

    if (_method == 'split') {
      if (_split.isEmpty) {
        _show('Add at least one payment allocation.');
        return;
      }
      var allocated = 0.0;
      for (final row in _split) {
        if (row.method == 'credit' && !widget.allowCredit) {
          _show('Walk-in customer cannot use credit.');
          return;
        }
        final amount = row.amount;
        if (amount <= 0) continue;
        allocations.add(
          MobilePaymentAllocation(
            methodCode: row.method,
            amount: amount,
            reference: row.reference.text.trim(),
          ),
        );
        allocated += amount;
      }
      if ((allocated - _total).abs() > 0.01) {
        _show('Split payments must equal ${_money(_total)}.');
        return;
      }
    } else if (_method == 'credit') {
      if (!widget.allowCredit) {
        _show('Walk-in customer cannot use credit.');
        return;
      }
      allocations.add(
        MobilePaymentAllocation(methodCode: 'credit', amount: _total),
      );
    } else {
      final received = _receivedValue;
      if (received < 0) {
        _show('Invalid payment amount.');
        return;
      }
      cashReceived = _method == 'cash' ? received : 0;
      final applied = received.clamp(0, _total).toDouble();
      if (!widget.allowCredit && applied + 0.01 < _total) {
        _show('Walk-in customer must be fully paid.');
        return;
      }
      if (_method != 'cash' && received > _total + 0.01) {
        _show('Only cash can be received above the invoice total.');
        return;
      }
      if (applied > 0.005) {
        allocations.add(
          MobilePaymentAllocation(
            methodCode: _method,
            amount: applied,
            reference: _reference.text.trim(),
          ),
        );
      }
      final credit = (_total - applied).clamp(0, double.infinity).toDouble();
      if (credit > 0.005) {
        if (!widget.allowCredit) {
          _show('Walk-in customer cannot use credit.');
          return;
        }
        allocations.add(
          MobilePaymentAllocation(methodCode: 'credit', amount: credit),
        );
      }
    }

    if (allocations.isEmpty) {
      _show('Choose a valid payment.');
      return;
    }

    Navigator.of(context).pop(
      MobilePaymentResult(
        discountAmount: _discountValue,
        roundOff: _roundOffValue,
        subtotal: _subtotal,
        tax: _tax,
        total: _total,
        cashReceived: cashReceived,
        allocations: allocations,
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    final compactHeader = width < 620;

    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back to cart',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: compactHeader
            ? const Text(
                'Payment',
                style: TextStyle(fontWeight: FontWeight.w900, color: _ink),
              )
            : const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment',
                    style: TextStyle(fontWeight: FontWeight.w900, color: _ink),
                  ),
                  Text(
                    'Review order, discounts and payment before completing the sale',
                    style: TextStyle(fontSize: 11, color: _muted),
                  ),
                ],
              ),
        actions: compactHeader
            ? null
            : [
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF7F2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        widget.customerName,
                        style: const TextStyle(
                          color: _success,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: _leftColumn()),
                    const SizedBox(width: 14),
                    Expanded(flex: 5, child: _rightColumn()),
                  ],
                )
              : Column(
                  children: [
                    _leftColumn(),
                    const SizedBox(height: 14),
                    _rightColumn(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _leftColumn() => Column(
        children: [
          _section(
            title: 'Order items',
            icon: Icons.receipt_long_outlined,
            child: Column(
              children: [
                for (var index = 0; index < widget.lines.length; index++) ...[
                  _orderLine(index + 1, widget.lines[index]),
                  if (index < widget.lines.length - 1)
                    const Divider(height: 1, color: _line),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _section(
            title: 'Order adjustments',
            icon: Icons.tune_rounded,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _discountMode,
                        decoration: const InputDecoration(
                          labelText: 'Discount type',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'amount',
                            child: Text('Amount'),
                          ),
                          DropdownMenuItem(
                            value: 'percent',
                            child: Text('Percentage'),
                          ),
                        ],
                        onChanged: (value) => setState(() {
                          _discountMode = value ?? 'amount';
                          _discount.text = '0';
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _discount,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Discount',
                          suffixText: _discountMode == 'percent'
                              ? '%'
                              : widget.currencyCode,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _roundOff,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Round off',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _autoRound,
                      icon: const Icon(Icons.auto_fix_high_rounded),
                      label: const Text('Auto'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Order note (optional)',
                    hintText: 'Add a note for this sale',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _rightColumn() => Column(
        children: [
          _section(
            title: 'Payment method',
            icon: Icons.payments_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _methodButton('cash', 'Cash', Icons.payments_rounded),
                    _methodButton('card', 'Card', Icons.credit_card_rounded),
                    _methodButton('upi', 'UPI', Icons.qr_code_2_rounded),
                    _methodButton(
                      'bank',
                      'Bank',
                      Icons.account_balance_rounded,
                    ),
                    _methodButton('credit', 'Credit', Icons.schedule_rounded),
                    _methodButton('split', 'Split', Icons.call_split_rounded),
                  ],
                ),
                const SizedBox(height: 14),
                if (_method == 'split') _splitEditor() else _singlePayment(),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _section(
            title: 'Order total',
            icon: Icons.calculate_outlined,
            child: Column(
              children: [
                _totalRow('Subtotal', _subtotal),
                _totalRow('Discount', -_discountValue),
                _totalRow('Tax', _tax),
                _totalRow('Round off', _roundOffValue),
                const Divider(height: 22, color: _line),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Total amount',
                        style: TextStyle(
                          fontSize: 17,
                          color: _ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      _money(_total),
                      style: const TextStyle(
                        fontSize: 21,
                        color: _accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back to cart'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _complete,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Complete sale'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: _success,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _singlePayment() {
    if (_method == 'credit') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFE1A3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFFA86A00)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'The full invoice will be posted to the customer account.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        TextField(
          controller: _received,
          onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: _method == 'cash' ? 'Amount received' : 'Amount paid',
            prefixText: '${widget.currencyCode} ',
            border: const OutlineInputBorder(),
          ),
        ),
        if (_method == 'cash') ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF9F3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Change due',
                    style: TextStyle(
                      color: _success,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  _money(_change),
                  style: const TextStyle(
                    color: _success,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _reference,
          decoration: const InputDecoration(
            labelText: 'Reference number (optional)',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _splitEditor() {
    final allocated = _split.fold<double>(0, (sum, row) => sum + row.amount);
    final balance = _total - allocated;
    return Column(
      children: [
        for (var index = 0; index < _split.length; index++) ...[
          _splitRow(index, _split[index]),
          if (index < _split.length - 1) const SizedBox(height: 8),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _addSplit,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add payment'),
            ),
            const Spacer(),
            Text(
              'Balance ${_money(balance)}',
              style: TextStyle(
                color: balance.abs() <= 0.01 ? _success : _muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _splitRow(int index, _SplitDraft row) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _line),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: row.method,
                    decoration: const InputDecoration(
                      labelText: 'Method',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'cash',
                        child: Text('Cash'),
                      ),
                      const DropdownMenuItem(
                        value: 'card',
                        child: Text('Card'),
                      ),
                      const DropdownMenuItem(
                        value: 'upi',
                        child: Text('UPI'),
                      ),
                      const DropdownMenuItem(
                        value: 'bank',
                        child: Text('Bank'),
                      ),
                      if (widget.allowCredit)
                        const DropdownMenuItem(
                          value: 'credit',
                          child: Text('Credit'),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      row.method = value ?? 'cash';
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: row.amountController,
                    onChanged: (_) => setState(() {}),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText: '${widget.currencyCode} ',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove payment',
                  onPressed:
                      _split.length <= 1 ? null : () => _removeSplit(index),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: row.reference,
              decoration: const InputDecoration(
                labelText: 'Reference (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      );

  Widget _methodButton(String code, String label, IconData icon) {
    final selected = _method == code;
    final disabled = code == 'credit' && !widget.allowCredit;
    return SizedBox(
      width: 104,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: disabled ? null : () => _setMethod(code),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF3FF) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _accent : _line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: disabled ? _muted.withValues(alpha: 0.45) : _accent,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: disabled ? _muted.withValues(alpha: 0.55) : _ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _orderLine(int index, MobilePaymentLine line) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '$index',
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${line.quantity.toStringAsFixed(line.quantity % 1 == 0 ? 0 : 2)} ${line.unitCode} × ${_money(line.unitPrice)}${line.sku.isEmpty ? '' : '  •  ${line.sku}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _money(line.gross),
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );

  Widget _totalRow(String label, double value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(color: _muted)),
            ),
            Text(
              _money(value),
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );

  Widget _section({
    required String title,
    required IconData icon,
    required Widget child,
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.025),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF3FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: _accent, size: 19),
                ),
                const SizedBox(width: 9),
                Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );
}

class _SplitDraft {
  String method;
  final TextEditingController amountController;
  final TextEditingController reference = TextEditingController();

  _SplitDraft({required this.method, required double amount})
      : amountController =
            TextEditingController(text: amount.toStringAsFixed(2));

  double get amount => double.tryParse(amountController.text.trim()) ?? 0;

  void dispose() {
    amountController.dispose();
    reference.dispose();
  }
}
