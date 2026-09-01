import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import '../services/location_scope_service.dart';

class OpeningBalancesV500Screen extends StatefulWidget {
  final ClientSession session;

  const OpeningBalancesV500Screen({super.key, required this.session});

  @override
  State<OpeningBalancesV500Screen> createState() =>
      _OpeningBalancesV500ScreenState();
}

class _OpeningLine {
  String? accountId;
  final debit = TextEditingController(text: '0.00');
  final credit = TextEditingController(text: '0.00');

  void dispose() {
    debit.dispose();
    credit.dispose();
  }
}

class _OpeningBalancesV500ScreenState
    extends State<OpeningBalancesV500Screen> {
  bool _loading = true;
  bool _posting = false;
  String? _error;
  List<Map<String, dynamic>> _accounts = const [];
  List<Map<String, dynamic>> _history = const [];
  final List<_OpeningLine> _lines = [_OpeningLine(), _OpeningLine()];
  DateTime _date = DateTime.now();

  List<Map<String, dynamic>> _maps(dynamic raw) {
    return raw is List
        ? raw
            .whereType<Map>()
            .map((x) => Map<String, dynamic>.from(x))
            .toList()
        : const [];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Supabase.instance.client;
      final result = await Future.wait([
        db.rpc(
          'accounting_accounts_list_v4',
          params: {'p_tenant_id': widget.session.business.id},
        ),
        db.rpc(
          'opening_balances_list_v500',
          params: {'p_tenant_id': widget.session.business.id},
        ),
      ]);
      _accounts = _maps(result[0]).where((x) => x['active'] == true).toList();
      _history = _maps(result[1]);
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _post() async {
    final rows = <Map<String, dynamic>>[];
    for (final line in _lines) {
      final debit = double.tryParse(line.debit.text.trim()) ?? 0;
      final credit = double.tryParse(line.credit.text.trim()) ?? 0;
      if (line.accountId == null || (debit <= 0 && credit <= 0)) {
        continue;
      }
      rows.add({
        'account_id': line.accountId,
        'debit': debit,
        'credit': credit,
        'description': 'Opening balance',
      });
    }

    if (rows.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter at least two opening-balance lines.'),
        ),
      );
      return;
    }

    final debitTotal = rows.fold<double>(
      0,
      (sum, row) => sum + ((row['debit'] as num).toDouble()),
    );
    final creditTotal = rows.fold<double>(
      0,
      (sum, row) => sum + ((row['credit'] as num).toDouble()),
    );
    if ((debitTotal - creditTotal).abs() > 0.004) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Opening balance is not balanced. Debit $debitTotal / Credit $creditTotal',
          ),
        ),
      );
      return;
    }

    setState(() => _posting = true);
    try {
      await Supabase.instance.client.rpc(
        'opening_balance_post_v500',
        params: {
          'p_tenant_id': widget.session.business.id,
          'p_entry_date': _date.toIso8601String().substring(0, 10),
          'p_lines': rows,
          'p_description': 'Opening balances',
          'p_location_id': LocationScopeService.currentForRead(widget.session),
        },
      );
      for (final line in _lines) {
        line.debit.text = '0.00';
        line.credit.text = '0.00';
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opening balances posted.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _posting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Opening Balances'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Opening date'),
                            subtitle: Text(
                              _date.toIso8601String().substring(0, 10),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.calendar_month),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _date,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setState(() => _date = picked);
                                }
                              },
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _posting ? null : _post,
                          icon: const Icon(Icons.save),
                          label: const Text('Post balanced opening'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._lines.asMap().entries.map((entry) {
                      final line = entry.value;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: line.accountId,
                                  decoration: InputDecoration(
                                    labelText: 'Account ${entry.key + 1}',
                                  ),
                                  items: _accounts
                                      .map(
                                        (account) => DropdownMenuItem<String>(
                                          value: account['id']?.toString(),
                                          child: Text(
                                            '${account['code']} • ${account['name']}',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() => line.accountId = value);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: line.debit,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  decoration:
                                      const InputDecoration(labelText: 'Debit'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: line.credit,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  decoration:
                                      const InputDecoration(labelText: 'Credit'),
                                ),
                              ),
                              if (_lines.length > 2)
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _lines.remove(line);
                                      line.dispose();
                                    });
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() => _lines.add(_OpeningLine()));
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add line'),
                      ),
                    ),
                    const Divider(),
                    const Text(
                      'Posted opening batches',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    ..._history.map(
                      (history) => ListTile(
                        dense: true,
                        title: Text(
                          '${history['entry_date']} • ${history['entry_number'] ?? ''}',
                        ),
                        subtitle: Text(
                          '${history['description'] ?? ''} • ${history['status'] ?? 'posted'}',
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
