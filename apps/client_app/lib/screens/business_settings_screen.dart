import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';

import '../models/client_session.dart';
import '../services/tenant_settings_service.dart';
import 'custom_fields_screen.dart';
import '../widgets/payment_method_ledger_settings.dart';

class BusinessSettingsScreen extends StatefulWidget {
  final ClientSession session;
  const BusinessSettingsScreen({super.key, required this.session});
  @override
  State<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends State<BusinessSettingsScreen> {
  final _service = TenantSettingsService();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _settings = {};

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('settings.manage');

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
      _settings = await _service.getSettings(widget.session.business.id);
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  T _value<T>(String key, T fallback) {
    final value = _settings[key];
    return value is T ? value : fallback;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.setSettings(widget.session.business.id, _settings);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Business settings saved. Sign out/in to refresh session-wide settings.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Business Settings',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Tenant-level behavior. These settings override platform/template defaults.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 22),
              _section('Business & GST Details', [
                TextFormField(
                  initialValue: _value(
                    'business.legal_name',
                    widget.session.business.name,
                  ),
                  enabled: _canManage,
                  decoration: const InputDecoration(
                    labelText: 'Legal Business Name',
                  ),
                  onChanged: (v) => _settings['business.legal_name'] = v,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _value('business.gstin', ''),
                        enabled: _canManage,
                        decoration: const InputDecoration(
                          labelText: 'GSTIN / Tax ID',
                        ),
                        onChanged: (v) => _settings['business.gstin'] = v,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: _value('business.phone', ''),
                        enabled: _canManage,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                        ),
                        onChanged: (v) => _settings['business.phone'] = v,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _value('business.email', ''),
                  enabled: _canManage,
                  decoration: const InputDecoration(
                    labelText: 'Business Email',
                  ),
                  onChanged: (v) => _settings['business.email'] = v,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _value('business.logo_url', ''),
                  enabled: _canManage,
                  decoration: const InputDecoration(
                    labelText: 'Business logo URL (optional)',
                    helperText:
                        'Used on invoice templates that show a logo. A branch logo overrides this.',
                  ),
                  onChanged: (v) => _settings['business.logo_url'] = v,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _value('business.address', ''),
                  enabled: _canManage,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Invoice Address',
                  ),
                  onChanged: (v) => _settings['business.address'] = v,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _value('business.state', ''),
                        enabled: _canManage,
                        decoration: const InputDecoration(labelText: 'State'),
                        onChanged: (v) => _settings['business.state'] = v,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: _value('business.state_code', ''),
                        enabled: _canManage,
                        decoration: const InputDecoration(
                          labelText: 'GST State Code',
                        ),
                        onChanged: (v) => _settings['business.state_code'] = v,
                      ),
                    ),
                  ],
                ),
              ]),
              const SizedBox(height: 16),
              _section('Sales & POS', [
                SwitchListTile(
                  title: const Text('Tax-inclusive selling prices'),
                  subtitle: const Text(
                    'When future invoice/POS pricing supports inclusive tax, treat displayed selling price as tax-inclusive.',
                  ),
                  value: _value('sales.tax_inclusive', false),
                  onChanged: !_canManage
                      ? null
                      : (v) => setState(
                          () => _settings['sales.tax_inclusive'] = v,
                        ),
                ),
                SwitchListTile(
                  title: const Text('Allow negative stock'),
                  value: _value('inventory.allow_negative_stock', false),
                  onChanged: !_canManage
                      ? null
                      : (v) => setState(
                          () => _settings['inventory.allow_negative_stock'] = v,
                        ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _value('pos.default_payment_method', 'cash'),
                  decoration: const InputDecoration(
                    labelText: 'POS default payment method',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'upi', child: Text('UPI')),
                    DropdownMenuItem(value: 'card', child: Text('Card')),
                    DropdownMenuItem(value: 'bank', child: Text('Bank')),
                    DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                    DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
                    DropdownMenuItem(value: 'credit', child: Text('Credit')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: !_canManage
                      ? null
                      : (v) {
                          if (v != null) {
                            setState(
                              () => _settings['pos.default_payment_method'] = v,
                            );
                          }
                        },
                ),
              ]),
              const SizedBox(height: 16),
              _section('Payment Methods & Ledger Mapping', [
                PaymentMethodLedgerSettings(
                  tenantId: widget.session.business.id,
                  canManage: _canManage,
                ),
              ]),
              const SizedBox(height: 16),
              _section('Documents', [
                TextFormField(
                  initialValue: _value('documents.invoice_footer', ''),
                  enabled: _canManage,
                  decoration: const InputDecoration(
                    labelText: 'Invoice footer',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _settings['documents.invoice_footer'] = v,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _value('documents.terms', ''),
                  enabled: _canManage,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Default terms / notes',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _settings['documents.terms'] = v,
                ),
              ]),
              const SizedBox(height: 16),
              _section('Customization', [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune_outlined),
                  title: const Text('Custom Fields'),
                  subtitle: const Text(
                    'Add business-specific fields without changing the ERP core.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          CustomFieldsScreen(session: widget.session),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              _section('Operations', [
                SwitchListTile(
                  title: const Text('Require approval for large discounts'),
                  value: _value('approvals.discount_enabled', false),
                  onChanged: !_canManage
                      ? null
                      : (v) => setState(
                          () => _settings['approvals.discount_enabled'] = v,
                        ),
                ),
                TextFormField(
                  initialValue: '${_value('approvals.discount_percent', 20)}',
                  enabled: _canManage,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Discount approval threshold %',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _settings['approvals.discount_percent'] =
                      double.tryParse(v) ?? 20,
                ),
              ]),
              const SizedBox(height: 16),
              _section('System', [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: const Text('THQ Business'),
                  subtitle: const Text('Installed application version'),
                  trailing: Text(
                    'v${ThqReleaseContract.appVersion} • Build ${ThqReleaseContract.buildNumber}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 20),
              if (_canManage)
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving...' : 'Save Settings'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );
}
