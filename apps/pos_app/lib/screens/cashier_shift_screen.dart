import 'package:flutter/material.dart';
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
                  subtitle: Text(DateFormat('dd MMM yyyy • hh:mm a').format(startAt)),
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
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Opening cash',
                    helperText: 'Cash physically in the drawer when the shift starts.',
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
      ScaffoldMessenger.of(context).showSnackBar(
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
      ScaffoldMessenger.of(context).showSnackBar(
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
    final expected = _number(_shift!['expected_cash_now'] ?? _shift!['expected_cash']);
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
                  subtitle: Text(DateFormat('dd MMM yyyy • hh:mm a').format(endAt)),
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
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Closing cash counted',
                    helperText: 'Enter the cash physically counted in the drawer.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Closing note (optional)'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _editShift(Map<String, dynamic> row) async {
    final isOpen = row['status']?.toString() == 'open';
    final isOwnOpen = isOpen && row['user_id']?.toString() == widget.session.userId;
    if (!isOwnOpen && !_canManageClosed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Owner or Shift Manage permission is required to edit this shift.')),
      );
      return;
    }

    var startAt = _time(row['opened_at']) ?? DateTime.now();
    var endAt = _time(row['closed_at']) ?? DateTime.now();
    final opening = TextEditingController(text: _number(row['opening_cash']).toStringAsFixed(2));
    final closing = TextEditingController(
      text: row['declared_cash'] == null ? '' : _number(row['declared_cash']).toStringAsFixed(2),
    );
    final note = TextEditingController(text: row['closing_note']?.toString() ?? '');
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
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Opening cash'),
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Closing cash'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      decoration: const InputDecoration(labelText: 'Closing note'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    decoration: const InputDecoration(
                      labelText: 'Reason for correction *',
                      helperText: 'Required. Stored permanently in the audit trail.',
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
                final closingValue = isOpen ? null : double.tryParse(closing.text.trim());
                if (openingValue == null || openingValue < 0) return;
                if (!isOpen && (closingValue == null || closingValue < 0)) return;
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
    if (accepted != true || openingValue == null || correctionReason.trim().isEmpty) return;

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
      ScaffoldMessenger.of(context).showSnackBar(
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
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cashier Shift', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                        SizedBox(height: 3),
                        Text('Cashier time and drawer accountability. Independent from Terminal Daily.'),
                      ],
                    ),
                  ),
                  IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${widget.session.device?.locationCode ?? ''} • ${widget.session.device?.deviceCode ?? ''} • ${widget.session.username}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!),
                  ),
                ),
              if (_shift == null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      children: [
                        const Icon(Icons.badge_outlined, size: 52),
                        const SizedBox(height: 12),
                        const Text('No active cashier shift', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 7),
                        const Text('Start time is automatic and opening cash is recorded. Both can be corrected with an audit trail.'),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _openShift,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start Shift'),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _shift!['shift_number']?.toString() ?? 'Current Shift',
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                                  ),
                                  Text('Started ${_dateTime(_shift!['opened_at'])} • ${_duration(_shift!)}'),
                                ],
                              ),
                            ),
                            const Chip(label: Text('OPEN')),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _editShift(_shift!),
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit start time / opening cash',
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _metric('Started With', _money(_shift!['opening_cash']), Icons.account_balance_wallet_outlined),
                            _metric('Expected Now', _money(_shift!['expected_cash_now'] ?? _shift!['expected_cash']), Icons.calculate_outlined),
                            _metric('Cash Sales', _money(_shift!['cash_sales']), Icons.receipt_long_outlined),
                            _metric('Customer Receipts', _money(_shift!['customer_receipts']), Icons.payments_outlined),
                            _metric('Cash In', _money(_shift!['cash_in']), Icons.add_circle_outline),
                            _metric('Cash Out', _money(_shift!['cash_out']), Icons.remove_circle_outline),
                            _metric('Expenses', _money(_shift!['cash_expenses']), Icons.money_off_outlined),
                            _metric('Refunds', _money(_shift!['refunds']), Icons.keyboard_return_outlined),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () => _cashMove('cash_in'),
                              icon: const Icon(Icons.add),
                              label: const Text('Cash In'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _cashMove('cash_out'),
                              icon: const Icon(Icons.remove),
                              label: const Text('Cash Out'),
                            ),
                            FilledButton.icon(
                              onPressed: _closeShift,
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: const Text('End Shift'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Text("Today's Shifts", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (_history.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(18), child: Text("No shifts recorded today. Historical shifts are available in Terminal Daily.")))
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < _history.length; i++) ...[
                        _shiftTile(_history[i]),
                        if (i != _history.length - 1) const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shiftTile(Map<String, dynamic> row) {
    final open = row['status']?.toString() == 'open';
    final canEdit = (open && row['user_id']?.toString() == widget.session.userId) || _canManageClosed;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      leading: CircleAvatar(
        child: Icon(open ? Icons.play_arrow : Icons.check, size: 19),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${row['shift_number'] ?? 'Shift'} • ${row['cashier_name']?.toString().isNotEmpty == true ? row['cashier_name'] : 'Cashier'}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(open ? 'OPEN' : 'CLOSED', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          'Start ${_dateTime(row['opened_at'])}\n'
          '${open ? 'Running' : 'End ${_dateTime(row['closed_at'])}'} • ${_duration(row)}\n'
          'Start ${_money(row['opening_cash'])}'
          '${open ? ' • Expected ${_money(row['expected_cash'])}' : ' • End ${_money(row['declared_cash'])} • Difference ${_money(row['difference'])}'}'
          '${_number(row['edit_count']) > 0 ? ' • Edited ${_number(row['edit_count']).toInt()}×' : ''}',
        ),
      ),
      isThreeLine: true,
      trailing: canEdit
          ? IconButton(
              onPressed: () => _editShift(row),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit shift',
            )
          : null,
    );
  }

  Widget _metric(String label, String value, IconData icon) => SizedBox(
    width: 190,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19),
            const SizedBox(height: 10),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    ),
  );
}
