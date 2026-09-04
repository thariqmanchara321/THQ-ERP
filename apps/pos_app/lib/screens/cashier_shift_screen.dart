import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:intl/intl.dart';

import '../models/client_session.dart';
import '../services/cashier_shift_service.dart';
import '../services/pos_completion_service.dart';
import '../services/pos_local_backup_service.dart';

class CashierShiftScreen extends StatefulWidget {
  final ClientSession session;

  const CashierShiftScreen({super.key, required this.session});

  @override
  State<CashierShiftScreen> createState() => _CashierShiftScreenState();
}

class _CashierShiftScreenState extends State<CashierShiftScreen> {
  final CashierShiftService _service = CashierShiftService();
  final PosCompletionService _completionService = PosCompletionService();
  final PosLocalBackupService _backupService = PosLocalBackupService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _shift;
  List<Map<String, dynamic>> _history = const [];

  String get _tenantId => widget.session.business.id;
  String get _deviceId => widget.session.device?.deviceId ?? '';
  String get _locationId => widget.session.device?.locationId ?? '';

  bool get _canManageClosed =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('pos.shift_manage');

  @override
  void initState() {
    super.initState();
    _load();
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

  DateTime? _time(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _dateTime(dynamic value) {
    final parsed = _time(value);
    if (parsed == null) return '-';
    return DateFormat('dd MMM yyyy • hh:mm a').format(parsed);
  }

  String _duration(Map<String, dynamic> row) {
    final start = _time(row['opened_at']);
    final end = _time(row['closed_at']) ?? DateTime.now();
    if (start == null || end.isBefore(start)) return '-';
    final duration = end.difference(start);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours}h ${minutes}m';
  }

  Future<void> _load() async {
    if (_deviceId.isEmpty) {
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
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final results = await Future.wait([
        _service.current(tenantId: _tenantId, deviceId: _deviceId),
        _service.history(
          tenantId: _tenantId,
          deviceId: _deviceId,
          from: today,
          to: today,
          limit: 50,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _shift = results[0] as Map<String, dynamic>?;
        _history = results[1] as List<Map<String, dynamic>>;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: initial,
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _openShift() async {
    var startAt = DateTime.now();
    final cash = TextEditingController(text: '0.00');
    final note = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Start Cashier Shift'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Start time is filled automatically. You can correct it before saving.',
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Shift start time'),
                  subtitle: Text(
                    DateFormat('dd MMM yyyy • hh:mm a').format(startAt),
                  ),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      final picked = await _pickDateTime(startAt);
                      if (picked != null) setLocalState(() => startAt = picked);
                    },
                    child: const Text('Edit'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cash,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Opening cash',
                    helperText:
                        'Cash physically in the drawer when the shift starts.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                    labelText: 'Start note (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final amount = double.tryParse(cash.text.trim());
                if (amount == null || amount < 0) return;
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Shift'),
            ),
          ],
        ),
      ),
    );
    final opening = double.tryParse(cash.text.trim());
    final openingNote = note.text;
    cash.dispose();
    note.dispose();
    if (accepted != true || opening == null) return;
    try {
      await _service.open(
        tenantId: _tenantId,
        locationId: _locationId,
        deviceId: _deviceId,
        openingCash: opening,
        openedAt: startAt,
        note: openingNote,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _cashMove(String type) async {
    if (_shift == null) return;
    final amount = TextEditingController();
    final note = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(type == 'cash_in' ? 'Cash In' : 'Cash Out'),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Reason / note'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(amount.text.trim());
              if (value == null || value <= 0) return;
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final value = double.tryParse(amount.text.trim());
    final text = note.text;
    amount.dispose();
    note.dispose();
    if (accepted != true || value == null || value <= 0) return;
    try {
      await _service.cashMove(
        tenantId: _tenantId,
        shiftId: _shift!['id'].toString(),
        type: type,
        amount: value,
        note: text,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _autoBackupAfterShiftClose() async {
    if (_deviceId.isEmpty) return;
    try {
      final prefs = await _completionService.getPreferences(
        tenantId: _tenantId,
        deviceId: _deviceId,
      );
      if (prefs['auto_backup_on_day_close'] == false) return;
      final folder = prefs['backup_folder']?.toString() ?? '';
      if (folder.isEmpty) return;
      await _backupService.backupNow(
        tenantId: _tenantId,
        businessName: widget.session.business.name,
        deviceCode: widget.session.device?.deviceCode ?? 'POS',
        folderPath: folder,
      );
    } catch (_) {
      // A backup path failure must not undo a successfully closed cashier shift.
    }
  }

  Future<void> _closeShift() async {
    if (_shift == null) return;
    var endAt = DateTime.now();
    final expected = _number(
      _shift!['expected_cash_now'] ?? _shift!['expected_cash'],
    );
    final cash = TextEditingController(text: expected.toStringAsFixed(2));
    final note = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('End Cashier Shift'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Expected cash: ${_money(expected)}'),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Shift end time'),
                  subtitle: Text(
                    DateFormat('dd MMM yyyy • hh:mm a').format(endAt),
                  ),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      final picked = await _pickDateTime(endAt);
                      if (picked != null) setLocalState(() => endAt = picked);
                    },
                    child: const Text('Edit'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cash,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Closing cash counted',
                    helperText:
                        'Enter the cash physically counted in the drawer.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                    labelText: 'Closing note (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final amount = double.tryParse(cash.text.trim());
                if (amount == null || amount < 0) return;
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End Shift'),
            ),
          ],
        ),
      ),
    );
    final closing = double.tryParse(cash.text.trim());
    final closingNote = note.text;
    cash.dispose();
    note.dispose();
    if (accepted != true || closing == null) return;
    try {
      final result = await _service.close(
        tenantId: _tenantId,
        shiftId: _shift!['id'].toString(),
        declaredCash: closing,
        closedAt: endAt,
        note: closingNote,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Shift Ended'),
          content: Text(
            'Started: ${_dateTime(result['opened_at'])}\n'
            'Ended: ${_dateTime(result['closed_at'])}\n\n'
            'Opening cash: ${_money(result['opening_cash'])}\n'
            'Expected cash: ${_money(result['expected_cash'])}\n'
            'Closing cash: ${_money(result['declared_cash'])}\n'
            'Difference: ${_money(result['difference'])}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      await _autoBackupAfterShiftClose();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _editShift(Map<String, dynamic> row) async {
    final isOpen = row['status']?.toString() == 'open';
    final isOwnOpen =
        isOpen && row['user_id']?.toString() == widget.session.userId;
    if (!isOwnOpen && !_canManageClosed) {
      ThqNotify.showSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Owner or Shift Manage permission is required to edit this shift.',
          ),
        ),
      );
      return;
    }

    var startAt = _time(row['opened_at']) ?? DateTime.now();
    var endAt = _time(row['closed_at']) ?? DateTime.now();
    final opening = TextEditingController(
      text: _number(row['opening_cash']).toStringAsFixed(2),
    );
    final closing = TextEditingController(
      text: row['declared_cash'] == null
          ? ''
          : _number(row['declared_cash']).toStringAsFixed(2),
    );
    final note = TextEditingController(
      text: row['closing_note']?.toString() ?? '',
    );
    final reason = TextEditingController();

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('Edit ${row['shift_number'] ?? 'Shift'}'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Corrections are allowed, but the original values are preserved in the shift audit history.',
                  ),
                  const SizedBox(height: 14),
                  _editableTimeTile(
                    label: 'Start time',
                    value: startAt,
                    onEdit: () async {
                      final picked = await _pickDateTime(startAt);
                      if (picked != null) setLocalState(() => startAt = picked);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: opening,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Opening cash',
                    ),
                  ),
                  if (!isOpen) ...[
                    const SizedBox(height: 12),
                    _editableTimeTile(
                      label: 'End time',
                      value: endAt,
                      onEdit: () async {
                        final picked = await _pickDateTime(endAt);
                        if (picked != null) setLocalState(() => endAt = picked);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: closing,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Closing cash',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      decoration: const InputDecoration(
                        labelText: 'Closing note',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    decoration: const InputDecoration(
                      labelText: 'Reason for correction *',
                      helperText:
                          'Required. Stored permanently in the audit trail.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final openingValue = double.tryParse(opening.text.trim());
                final closingValue = isOpen
                    ? null
                    : double.tryParse(closing.text.trim());
                if (openingValue == null || openingValue < 0) return;
                if (!isOpen && (closingValue == null || closingValue < 0)) {
                  return;
                }
                if (reason.text.trim().isEmpty) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save Correction'),
            ),
          ],
        ),
      ),
    );

    final openingValue = double.tryParse(opening.text.trim());
    final closingValue = isOpen ? null : double.tryParse(closing.text.trim());
    final closingNote = note.text;
    final correctionReason = reason.text;
    opening.dispose();
    closing.dispose();
    note.dispose();
    reason.dispose();
    if (accepted != true ||
        openingValue == null ||
        correctionReason.trim().isEmpty) {
      return;
    }

    try {
      await _service.edit(
        tenantId: _tenantId,
        shiftId: row['id'].toString(),
        openedAt: startAt,
        openingCash: openingValue,
        closedAt: isOpen ? null : endAt,
        declaredCash: closingValue,
        note: closingNote,
        reason: correctionReason,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Widget _editableTimeTile({
    required String label,
    required DateTime value,
    required VoidCallback onEdit,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.schedule_outlined),
      title: Text(label),
      subtitle: Text(DateFormat('dd MMM yyyy • hh:mm a').format(value)),
      trailing: OutlinedButton(onPressed: onEdit, child: const Text('Edit')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

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
                        'Cashier Shift',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${widget.session.device?.locationCode ?? ''} | '
                        '${widget.session.device?.deviceCode ?? ''} | '
                        '${widget.session.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_shift == null)
                  FilledButton.icon(
                    onPressed: _openShift,
                    icon: const Icon(Icons.play_arrow, size: 15),
                    label: const Text('Start Shift'),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: () => _cashMove('cash_in'),
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('Cash In'),
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton.icon(
                    onPressed: () => _cashMove('cash_out'),
                    icon: const Icon(Icons.remove, size: 15),
                    label: const Text('Cash Out'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: _closeShift,
                    icon: const Icon(Icons.stop_circle_outlined, size: 15),
                    label: const Text('End Shift'),
                  ),
                ],
                const SizedBox(width: 3),
                IconButton(
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: TextStyle(fontSize: 11, color: scheme.onErrorContainer),
              ),
            ),
          ],
          const SizedBox(height: 5),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 900;

                final current = _currentShiftPanel();
                final history = _historyPanel();

                if (stacked) {
                  return Column(
                    children: [
                      Expanded(child: current),
                      const SizedBox(height: 5),
                      Expanded(child: history),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 6, child: current),
                    const SizedBox(width: 5),
                    Expanded(flex: 5, child: history),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _currentShiftPanel() {
    final scheme = Theme.of(context).colorScheme;

    if (_shift == null) {
      return Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.badge_outlined, size: 34, color: scheme.outline),
              const SizedBox(height: 7),
              const Text(
                'No active cashier shift',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Record opening cash before billing.',
                style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _openShift,
                icon: const Icon(Icons.play_arrow, size: 15),
                label: const Text('Start Shift'),
              ),
            ],
          ),
        ),
      );
    }

    final metrics = <Widget>[
      _metric(
        'Started With',
        _money(_shift!['opening_cash']),
        Icons.account_balance_wallet_outlined,
      ),
      _metric(
        'Expected Now',
        _money(_shift!['expected_cash_now'] ?? _shift!['expected_cash']),
        Icons.calculate_outlined,
      ),
      _metric(
        'Cash Sales',
        _money(_shift!['cash_sales']),
        Icons.receipt_long_outlined,
      ),
      _metric(
        'Customer Receipts',
        _money(_shift!['customer_receipts']),
        Icons.payments_outlined,
      ),
      _metric('Cash In', _money(_shift!['cash_in']), Icons.add_circle_outline),
      _metric(
        'Cash Out',
        _money(_shift!['cash_out']),
        Icons.remove_circle_outline,
      ),
      _metric(
        'Expenses',
        _money(_shift!['cash_expenses']),
        Icons.money_off_outlined,
      ),
      _metric(
        'Refunds',
        _money(_shift!['refunds']),
        Icons.keyboard_return_outlined,
      ),
    ];

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
                const Icon(Icons.badge_outlined, size: 16),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _shift!['shift_number']?.toString() ?? 'Current Shift',
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Started ${_dateTime(_shift!['opened_at'])} | '
                        '${_duration(_shift!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 23,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'OPEN',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit shift',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _editShift(_shift!),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(7),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 650 ? 4 : 2;
                  const gap = 5.0;
                  final width =
                      (constraints.maxWidth - ((columns - 1) * gap)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: metrics
                        .map((widget) => SizedBox(width: width, child: widget))
                        .toList(),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyPanel() {
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
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            color: scheme.surfaceContainerHighest.withValues(alpha: .42),
            child: Row(
              children: [
                const Icon(Icons.history, size: 15),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    "TODAY'S SHIFTS",
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .35,
                    ),
                  ),
                ),
                Text(
                  '${_history.length}',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _history.isEmpty
                ? Center(
                    child: Text(
                      'No shifts recorded today.',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _history.length,
                    itemBuilder: (context, index) =>
                        _shiftTile(_history[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _shiftTile(Map<String, dynamic> row) {
    final scheme = Theme.of(context).colorScheme;
    final open = row['status']?.toString() == 'open';
    final canEdit =
        (open && row['user_id']?.toString() == widget.session.userId) ||
        _canManageClosed;

    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(
            width: 27,
            height: 27,
            decoration: BoxDecoration(
              color: open
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(open ? Icons.play_arrow : Icons.check, size: 15),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['shift_number'] ?? 'Shift'} | '
                  '${row['cashier_name']?.toString().isNotEmpty == true ? row['cashier_name'] : 'Cashier'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  open
                      ? '${_dateTime(row['opened_at'])} | '
                            'Expected ${_money(row['expected_cash'])}'
                      : '${_dateTime(row['opened_at'])} - '
                            '${_dateTime(row['closed_at'])} | '
                            'Diff ${_money(row['difference'])}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            open ? 'OPEN' : 'CLOSED',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: open ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          if (canEdit)
            IconButton(
              tooltip: 'Edit shift',
              visualDensity: VisualDensity.compact,
              onPressed: () => _editShift(row),
              icon: const Icon(Icons.edit_outlined, size: 14),
            ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 57,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
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
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
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
