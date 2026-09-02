import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin-only editor for v6.0 audit thresholds.
///
/// Backend permissions remain authoritative. Rendering this screen does not
/// grant configure access; audit_risk_config_set_v600 enforces it server-side.
class AuditRiskSettingsScreen extends StatefulWidget {
  const AuditRiskSettingsScreen({super.key, required this.tenantId});

  final String tenantId;

  @override
  State<AuditRiskSettingsScreen> createState() =>
      _AuditRiskSettingsScreenState();
}

class _AuditRiskSettingsScreenState extends State<AuditRiskSettingsScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _discountReview = TextEditingController();
  final _discountHigh = TextEditingController();
  final _stockReview = TextEditingController();
  final _stockHigh = TextEditingController();
  final _backdateReview = TextEditingController();
  final _backdateHigh = TextEditingController();

  bool _negativeMarginHigh = true;
  bool _manualJournalReview = true;
  bool _postedPurchaseEditReview = true;
  bool _paymentEditHigh = true;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _discountReview,
      _discountHigh,
      _stockReview,
      _stockHigh,
      _backdateReview,
      _backdateHigh,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _client.rpc(
        'audit_risk_config_get_v600',
        params: {'p_tenant_id': widget.tenantId},
      );
      final data = raw is Map
          ? raw.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
      _discountReview.text = (data['discount_review_pct'] ?? 10).toString();
      _discountHigh.text = (data['discount_high_pct'] ?? 20).toString();
      _stockReview.text = (data['stock_adjustment_review_value'] ?? 10000)
          .toString();
      _stockHigh.text = (data['stock_adjustment_high_value'] ?? 50000)
          .toString();
      _backdateReview.text = (data['backdate_review_days'] ?? 1).toString();
      _backdateHigh.text = (data['backdate_high_days'] ?? 7).toString();
      _negativeMarginHigh = data['negative_margin_high'] != false;
      _manualJournalReview = data['manual_journal_review'] != false;
      _postedPurchaseEditReview = data['posted_purchase_edit_review'] != false;
      _paymentEditHigh = data['payment_edit_high'] != false;
    } catch (error) {
      _error = error;
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _client.rpc(
        'audit_risk_config_set_v600',
        params: {
          'p_tenant_id': widget.tenantId,
          'p_config': {
            'discount_review_pct': double.parse(_discountReview.text),
            'discount_high_pct': double.parse(_discountHigh.text),
            'stock_adjustment_review_value': double.parse(_stockReview.text),
            'stock_adjustment_high_value': double.parse(_stockHigh.text),
            'backdate_review_days': int.parse(_backdateReview.text),
            'backdate_high_days': int.parse(_backdateHigh.text),
            'negative_margin_high': _negativeMarginHigh,
            'manual_journal_review': _manualJournalReview,
            'posted_purchase_edit_review': _postedPurchaseEditReview,
            'payment_edit_high': _paymentEditHigh,
          },
        },
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audit risk thresholds updated.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  String? _positiveNumber(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 0) {
      return 'Enter a valid non-negative number';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Risk Settings')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Risk thresholds identify unusual activity for review. They do not declare fraud or wrongdoing.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error.toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            _pair(
              _numberField(
                _discountReview,
                'Discount review %',
                _positiveNumber,
              ),
              _numberField(
                _discountHigh,
                'Discount high-risk %',
                _positiveNumber,
              ),
            ),
            const SizedBox(height: 12),
            _pair(
              _numberField(
                _stockReview,
                'Stock adjustment review value',
                _positiveNumber,
              ),
              _numberField(
                _stockHigh,
                'Stock adjustment high-risk value',
                _positiveNumber,
              ),
            ),
            const SizedBox(height: 12),
            _pair(
              _numberField(
                _backdateReview,
                'Backdated review days',
                _positiveNumber,
              ),
              _numberField(
                _backdateHigh,
                'Backdated high-risk days',
                _positiveNumber,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _negativeMarginHigh,
              onChanged: (v) => setState(() => _negativeMarginHigh = v),
              title: const Text('Negative margin is High Risk'),
            ),
            SwitchListTile(
              value: _manualJournalReview,
              onChanged: (v) => setState(() => _manualJournalReview = v),
              title: const Text('Manual journals Need Review'),
            ),
            SwitchListTile(
              value: _postedPurchaseEditReview,
              onChanged: (v) => setState(() => _postedPurchaseEditReview = v),
              title: const Text('Posted purchase edits Need Review'),
            ),
            SwitchListTile(
              value: _paymentEditHigh,
              onChanged: (v) => setState(() => _paymentEditHigh = v),
              title: const Text('Posted payment edits are High Risk'),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Risk Rules'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label,
    String? Function(String?) validator,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _pair(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Column(children: [left, const SizedBox(height: 12), right]);
        }
        return Row(
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}
