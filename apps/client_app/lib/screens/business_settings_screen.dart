import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:erp_core/erp_core.dart';

import '../models/client_session.dart';
import '../services/tenant_settings_service.dart';
import '../services/invoice_template_service.dart';
import '../widgets/additional_charges_dialog.dart';
import 'custom_fields_screen.dart';
import '../widgets/payment_method_ledger_settings.dart';

class BusinessSettingsScreen extends StatefulWidget {
  final ClientSession session;
  final ValueChanged<Map<String, dynamic>>? onSettingsSaved;
  const BusinessSettingsScreen({
    super.key,
    required this.session,
    this.onSettingsSaved,
  });
  @override
  State<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends State<BusinessSettingsScreen> {
  final _service = TenantSettingsService();
  final _templateService = InvoiceTemplateService();
  final TextEditingController _logoController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _uploadingLogo = false;
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

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _settings = await _service.getSettings(widget.session.business.id);
      _logoController.text = _value('business.logo_url', '');
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

  Future<void> _pickAndUploadLogo() async {
    if (!_canManage || _uploadingLogo) return;
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Logo image',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      final ext = file.name.contains('.')
          ? file.name.split('.').last.toLowerCase()
          : 'png';
      if (!const {'png', 'jpg', 'jpeg', 'webp'}.contains(ext)) {
        if (!mounted) return;
        ThqNotify.error(context, 'Please choose a PNG, JPG, or WEBP image.');
        return;
      }
      setState(() => _uploadingLogo = true);
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.lengthInBytes > 5 * 1024 * 1024) {
        ThqNotify.error(context, 'Logo image must be smaller than 5 MB.');
        return;
      }

      String logoUrl = '';
      try {
        logoUrl = await _templateService.uploadBusinessLogo(
          tenantId: widget.session.business.id,
          bytes: bytes,
          extension: ext == 'webp' ? 'png' : ext,
        );
      } catch (_) {
        // Fallback: encode as base64 data URI so logo works even without cloud storage
        final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
        logoUrl = 'data:$mime;base64,${base64Encode(bytes)}';
      }

      if (!mounted) return;
      setState(() {
        _settings['business.logo_url'] = logoUrl;
        _logoController.text = logoUrl;
      });
      ThqNotify.success(
        context,
        'Logo selected. Click "Save Settings" below to apply across all devices.',
      );
    } catch (e) {
      if (mounted) ThqNotify.error(context, 'Error selecting logo: $e');
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  void _removeLogo() {
    setState(() {
      _settings['business.logo_url'] = '';
      _logoController.text = '';
    });
    ThqNotify.info(
      context,
      'Logo removed. Click "Save Settings" below to apply.',
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _settings['business.logo_url'] = _logoController.text.trim();
      await _service.setSettings(widget.session.business.id, _settings);
      try {
        widget.session.settings['business.logo_url'] =
            _settings['business.logo_url'];
      } catch (_) {}
      widget.onSettingsSaved?.call(_settings);
      if (!mounted) return;
      ThqNotify.success(
        context,
        'Business settings and logo saved successfully.',
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
                _buildLogoCard(),
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
              _section('Additional Charges', [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enable Additional Charges',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'One switch controls Client Sales, POS and Restaurant billing.',
                          ),
                        ],
                      ),
                    ),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(value: false, label: Text('No')),
                        ButtonSegment<bool>(value: true, label: Text('Yes')),
                      ],
                      selected: <bool>{
                        _value('sales.additional_charges_enabled', true),
                      },
                      onSelectionChanged: !_canManage
                          ? null
                          : (values) {
                              if (values.isEmpty) return;
                              setState(
                                () =>
                                    _settings['sales.additional_charges_enabled'] =
                                        values.first,
                              );
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add_card_outlined),
                  title: const Text('Manage Additional Charges'),
                  subtitle: const Text(
                    'Add Packaging, Delivery, Service, Handling, Convenience '
                    'or your own custom charge. The same catalogue is shared '
                    'by Client, POS and Restaurant.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: !_canManage
                      ? null
                      : () async {
                          await showThqDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => AdditionalChargesDialog(
                              session: widget.session,
                            ),
                          );
                        },
                ),
                const SizedBox(height: 6),
                const Text(
                  'Charge defaults are saved centrally. During billing the '
                  'amount can be edited for that invoice while GST remains '
                  'calculated through the classified service item.',
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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

  Widget _buildLogoCard() {
    final logoVal = _logoController.text.trim();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ThqBusinessLogo(
                logoUrl: logoVal,
                size: 64,
                borderRadius: BorderRadius.circular(14),
                backgroundColor: Colors.white,
                borderColor: scheme.outlineVariant,
                fallback: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 28,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Business Logo',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Visible on the sidebar across all 4 devices (Client Desktop, Client Mobile, POS, and Mobile POS) and printed receipts.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _canManage && !_uploadingLogo ? _pickAndUploadLogo : null,
                          icon: _uploadingLogo
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.upload_rounded, size: 16),
                          label: Text(
                            _uploadingLogo
                                ? 'Uploading...'
                                : (logoVal.isNotEmpty ? 'Change Logo' : 'Upload Logo'),
                          ),
                        ),
                        if (logoVal.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: _canManage && !_uploadingLogo ? _removeLogo : null,
                            icon: const Icon(Icons.delete_outline_rounded, size: 16),
                            label: const Text('Remove'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _logoController,
            enabled: _canManage && !_uploadingLogo,
            decoration: const InputDecoration(
              labelText: 'Logo Image URL',
              prefixIcon: Icon(Icons.link_rounded),
              helperText: 'Upload a logo file above, or paste an external HTTPS image URL.',
            ),
            onChanged: (v) {
              setState(() {
                _settings['business.logo_url'] = v.trim();
              });
            },
          ),
        ],
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
