import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';

class BankReconciliationV500Screen extends StatefulWidget {
  final ClientSession session;
  final Map<String, dynamic> bank;
  const BankReconciliationV500Screen({
    super.key,
    required this.session,
    required this.bank,
  });

  @override
  State<BankReconciliationV500Screen> createState() =>
      _BankReconciliationV500ScreenState();
}

class _BankReconciliationV500ScreenState
    extends State<BankReconciliationV500Screen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _lines = const [];
  List<Map<String, dynamic>> _journals = const [];

  List<Map<String, dynamic>> _maps(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList()
      : const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Supabase.instance.client;
      final r = await Future.wait([
        db.rpc(
          'bank_statement_list_v500',
          params: {
            'p_tenant_id': widget.session.business.id,
            'p_bank_account_id': widget.bank['id'],
            'p_status': null,
          },
        ),
        db.rpc(
          'journal_center_list_v500',
          params: {'p_tenant_id': widget.session.business.id, 'p_limit': 500},
        ),
      ]);
      _lines = _maps(r[0]);
      _journals = _maps(
        r[1],
      ).where((j) => j['status']?.toString() == 'posted').toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addLine() async {
    final amount = TextEditingController();
    final reference = TextEditingController();
    final description = TextEditingController();
    var date = DateTime.now();
    var direction = 'credit';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Add bank statement line'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Transaction date'),
                  subtitle: Text(date.toIso8601String().substring(0, 10)),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_month),
                    onPressed: () async {
                      final x = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (x != null) setDialog(() => date = x);
                    },
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: direction,
                  decoration: const InputDecoration(
                    labelText: 'Bank statement direction',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'credit',
                      child: Text('Credit / money in'),
                    ),
                    DropdownMenuItem(
                      value: 'debit',
                      child: Text('Debit / money out'),
                    ),
                  ],
                  onChanged: (v) => setDialog(() => direction = v ?? 'credit'),
                ),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(labelText: 'Reference'),
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description'),
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
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final value = double.tryParse(amount.text.trim());
    final ref = reference.text.trim();
    final desc = description.text.trim();
    amount.dispose();
    reference.dispose();
    description.dispose();
    if (ok != true || value == null || value <= 0) return;
    try {
      await Supabase.instance.client.rpc(
        'bank_statement_line_save_v500',
        params: {
          'p_tenant_id': widget.session.business.id,
          'p_line_id': null,
          'p_bank_account_id': widget.bank['id'],
          'p_transaction_date': date.toIso8601String().substring(0, 10),
          'p_direction': direction,
          'p_amount': value,
          'p_reference': ref,
          'p_description': desc,
        },
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _match(Map<String, dynamic> line) async {
    String? selected;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Match posted journal'),
          content: SizedBox(
            width: 620,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Journal'),
              items: _journals
                  .map(
                    (j) => DropdownMenuItem(
                      value: j['journal_id']?.toString() ?? j['id']?.toString(),
                      child: Text(
                        '${j['entry_number'] ?? ''} • ${j['entry_date'] ?? ''} • ${j['description'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setDialog(() => selected = v),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Match'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || selected == null) return;
    try {
      await Supabase.instance.client.rpc(
        'bank_statement_match_v500',
        params: {
          'p_tenant_id': widget.session.business.id,
          'p_line_id': line['id'],
          'p_journal_id': selected,
        },
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        'Bank Reconciliation • ${widget.bank['account_name'] ?? widget.bank['name'] ?? ''}',
      ),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
        FilledButton.icon(
          onPressed: _addLine,
          icon: const Icon(Icons.add),
          label: const Text('Statement line'),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!))
        : _lines.isEmpty
        ? const Center(child: Text('No bank statement lines.'))
        : ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _lines.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final x = _lines[i];
              final matched = x['status'] == 'matched';
              return ListTile(
                leading: Icon(
                  matched ? Icons.verified_outlined : Icons.rule_outlined,
                ),
                title: Text(
                  '${x['transaction_date']} • ${x['direction']} • ${x['amount']}',
                ),
                subtitle: Text(
                  '${x['reference'] ?? ''} ${x['description'] ?? ''}${matched ? ' • ${x['entry_number'] ?? ''}' : ''}',
                ),
                trailing: matched
                    ? const Chip(label: Text('Matched'))
                    : FilledButton.tonal(
                        onPressed: () => _match(x),
                        child: const Text('Match'),
                      ),
              );
            },
          ),
  );
}
