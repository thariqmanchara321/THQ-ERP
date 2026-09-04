import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/accounting_service.dart';

class PaymentMethodLedgerSettings extends StatefulWidget {
  const PaymentMethodLedgerSettings({
    super.key,
    required this.tenantId,
    required this.canManage,
  });

  final String tenantId;
  final bool canManage;

  @override
  State<PaymentMethodLedgerSettings> createState() =>
      _PaymentMethodLedgerSettingsState();
}

class _PaymentMethodLedgerSettingsState
    extends State<PaymentMethodLedgerSettings> {
  final AccountingService _accounting = AccountingService();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _accounts = const [];
  List<Map<String, dynamic>> _methods = const [];

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
      final accountsFuture = _accounting.accounts(tenantId: widget.tenantId);
      final methodsFuture = Supabase.instance.client.rpc(
        'payment_methods_list_v522',
        params: {'p_tenant_id': widget.tenantId},
      );
      final accounts = await accountsFuture;
      final raw = await methodsFuture;
      if (!mounted) return;
      setState(() {
        _accounts = accounts.where((e) => e['active'] != false).toList();
        _methods = (raw as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      for (final method in _methods) {
        final code = method['code']?.toString() ?? '';
        await Supabase.instance.client.rpc(
          'payment_method_save_v522',
          params: {
            'p_tenant_id': widget.tenantId,
            'p_code': code,
            'p_display_name':
                method['display_name']?.toString() ?? code.toUpperCase(),
            'p_ledger_account_id': code == 'credit'
                ? null
                : method['ledger_account_id'],
            'p_active': method['active'] != false,
            'p_sort_order': (method['sort_order'] as num?)?.toInt() ?? 0,
          },
        );
      }
      if (!mounted) return;
      ThqNotify.success(context, 'Payment ledger mappings saved.');
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LinearProgressIndicator();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Each settlement method debits its configured ledger. Credit is '
          'not a settlement and remains in Accounts Receivable.',
        ),
        const SizedBox(height: 12),
        for (final method in _methods) ...[
          _row(method),
          const SizedBox(height: 8),
        ],
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (widget.canManage)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.account_balance_outlined),
              label: Text(_saving ? 'Saving…' : 'Save Payment Mappings'),
            ),
          ),
      ],
    );
  }

  Widget _row(Map<String, dynamic> method) {
    final code = method['code']?.toString() ?? '';
    final credit = code == 'credit';
    return LayoutBuilder(
      builder: (context, constraints) {
        final toggle = SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(
            method['display_name']?.toString() ?? code.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            credit
                ? 'Accounts Receivable • automatic'
                : code == 'cash'
                ? 'Cash can over-tender; excess is change.'
                : 'Electronic/non-cash overpayment is rejected.',
          ),
          value: method['active'] != false,
          onChanged: !widget.canManage
              ? null
              : (value) => setState(() => method['active'] = value),
        );

        final ledger = DropdownButtonFormField<String>(
          initialValue: credit ? null : method['ledger_account_id']?.toString(),
          isExpanded: true,
          decoration: InputDecoration(
            labelText: credit
                ? 'Accounts Receivable (automatic)'
                : 'Debit ledger',
            border: const OutlineInputBorder(),
          ),
          items: _accounts
              .map(
                (account) => DropdownMenuItem<String>(
                  value: account['id']?.toString(),
                  child: Text(
                    '${account['code'] ?? ''} • ${account['name'] ?? ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: !widget.canManage || credit
              ? null
              : (value) => setState(() => method['ledger_account_id'] = value),
        );

        if (constraints.maxWidth < 680) {
          return Column(children: [toggle, const SizedBox(height: 6), ledger]);
        }
        return Row(
          children: [
            Expanded(flex: 2, child: toggle),
            const SizedBox(width: 12),
            Expanded(flex: 3, child: ledger),
          ],
        );
      },
    );
  }
}
