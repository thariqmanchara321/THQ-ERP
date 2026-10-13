import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/admin_home_button.dart';
import '../models/platform_models.dart';
import '../services/business_service.dart';
import '../services/owner_service.dart';
import '../services/platform_config_service.dart';

class CreateBusinessScreen extends StatefulWidget {
  const CreateBusinessScreen({super.key});
  @override
  State<CreateBusinessScreen> createState() => _CreateBusinessScreenState();
}

class _CreateBusinessScreenState extends State<CreateBusinessScreen> {
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _ownerUsernameController = TextEditingController(text: 'admin');
  final _ownerPasswordController = TextEditingController();
  final _ownerPhoneController = TextEditingController();
  final _ownerEmailController = TextEditingController();
  final _storeNameController = TextEditingController(text: 'Main');
  final _storeCodeController = TextEditingController(text: 'MAIN');
  final _gstinController = TextEditingController();

  final _businessService = BusinessService();
  final _ownerService = OwnerService();
  final _platformService = PlatformConfigService();

  late Future<
    (
      List<PlatformModuleInfo>,
      List<BusinessTemplate>,
      List<SubscriptionPlan>,
      List<Map<String, dynamic>>,
    )
  > _future;

  final Set<String> _selectedModules = {'dashboard'};
  String _businessType = 'General Retail';
  String? _templateKey;
  String? _planId;
  String? _divisionId;
  bool _newDivision = false;
  String _divisionRole = 'child';
  bool _slugEditedManually = false;
  bool _saving = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _nameController.addListener(_updateSlug);
  }

  Future<
    (
      List<PlatformModuleInfo>,
      List<BusinessTemplate>,
      List<SubscriptionPlan>,
      List<Map<String, dynamic>>,
    )
  > _load() async {
    final modules = await _platformService.getModules();
    final templates = await _platformService.getTemplates();
    final plans = await _platformService.getPlans();
    final divisions = await _businessService.getDivisions();
    return (modules, templates, plans, divisions);
  }

  void _updateSlug() {
    if (_slugEditedManually) return;
    _slugController.text = _nameController.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  void _applyTemplate(BusinessTemplate template) {
    setState(() {
      _templateKey = template.key;
      _businessType = template.businessType;
      _selectedModules
        ..clear()
        ..addAll(template.moduleKeys)
        ..add('dashboard');
    });
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    final ownerUser = _ownerUsernameController.text.trim().toLowerCase();
    final ownerPass = _ownerPasswordController.text;

    if (name.isEmpty) {
      setState(() => _error = 'Business name is required.');
      return;
    }
    if (ownerUser.length < 3) {
      setState(() => _error = 'Owner username must be at least 3 characters.');
      return;
    }
    if (ownerPass.length < 6) {
      setState(() => _error = 'Owner password must be at least 6 characters.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final res = await _businessService.createBusinessV709(
        name: name,
        businessType: _businessType,
        ownerUsername: ownerUser,
        ownerPassword: ownerPass,
        ownerPhone: _ownerPhoneController.text.trim(),
        ownerEmail: _ownerEmailController.text.trim(),
        storeName: _storeNameController.text.trim(),
        storeCode: _storeCodeController.text.trim(),
        moduleKeys: _selectedModules.toList(),
        gstin: _gstinController.text.trim(),
      );

      final tenantId = res['tenant_id']?.toString() ?? '';
      if (tenantId.isNotEmpty && ownerUser.isNotEmpty && ownerPass.isNotEmpty) {
        await _ownerService.createOwner(
          tenantId: tenantId,
          name: '$name Admin',
          username: ownerUser,
          password: ownerPass,
        );
      }
      if (_templateKey != null && tenantId.isNotEmpty) {
        try {
          await _businessService.applyTemplateSettings(
            tenantId: tenantId,
            templateKey: _templateKey!,
          );
        } catch (_) {}
      }
      if (_planId != null && tenantId.isNotEmpty) {
        try {
          await _platformService.setTenantSubscription(
            tenantId: tenantId,
            planId: _planId!,
            status: 'trial',
            billingCycle: 'monthly',
          );
        } catch (_) {}
      }

      if (_newDivision && tenantId.isNotEmpty) {
        final divisionId = await _businessService.saveDivision(
          name: '$name Division',
        );
        await _businessService.assignBusinessToDivision(
          tenantId: tenantId,
          divisionId: divisionId,
          memberType: 'main',
        );
      } else if (_divisionId != null && tenantId.isNotEmpty) {
        await _businessService.assignBusinessToDivision(
          tenantId: tenantId,
          divisionId: _divisionId!,
          memberType: _divisionRole,
        );
      }

      if (!mounted) return;

      await _showActivationCodesDialog(res);

      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showActivationCodesDialog(Map<String, dynamic> res) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 10),
            const Text('Business Created & Activated'),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${res['name']} has been provisioned successfully! Use these credentials and codes to activate workstations on-site.',
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              _codeTile(
                context,
                title: 'Business Code',
                code: res['business_code']?.toString() ?? '',
                subtitle: 'Enter on any Client PC or POS when activating.',
              ),
              const SizedBox(height: 10),
              _codeTile(
                context,
                title: 'Client PC Activation Code',
                code: res['client_activation_code']?.toString() ?? '',
                subtitle: 'Device: ${res['client_device_code'] ?? 'CLIENT-1'} (Store: ${res['store_name']})',
              ),
              const SizedBox(height: 10),
              _codeTile(
                context,
                title: 'POS Terminal Activation Code',
                code: res['pos_activation_code']?.toString() ?? '',
                subtitle: 'Device: ${res['pos_device_code'] ?? 'POS-1'} (Store: ${res['store_name']})',
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 20, color: Colors.indigo),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Owner User: ${res['owner_username']} • Default Store: ${res['store_name']}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Done & Continue'),
          ),
        ],
      ),
    );
  }

  Widget _codeTile(
    BuildContext context, {
    required String title,
    required String code,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  code,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy to clipboard',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied $title: $code'), duration: const Duration(seconds: 2)),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.removeListener(_updateSlug);
    _nameController.dispose();
    _slugController.dispose();
    _ownerUsernameController.dispose();
    _ownerPasswordController.dispose();
    _ownerPhoneController.dispose();
    _ownerEmailController.dispose();
    _storeNameController.dispose();
    _storeCodeController.dispose();
    _gstinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Business'),
        actions: const [AdminHomeButton()],
      ),
      body: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error loading platform config: ${snapshot.error}'));
          }
          final (modules, templates, plans, divisions) = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Business Details Section
                    const Text(
                      '1. Business Details',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Business Name *',
                              hintText: 'e.g. Tenzo Traders',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: _slugController,
                            onChanged: (_) => _slugEditedManually = true,
                            decoration: const InputDecoration(
                              labelText: 'Business URL / Slug *',
                              hintText: 'e.g. tenzo-traders',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: _templateKey,
                            decoration: const InputDecoration(
                              labelText: 'Business Template',
                              border: OutlineInputBorder(),
                              helperText: 'Preselects modules and default workflows.',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Custom / General Retail'),
                              ),
                              ...templates.map(
                                (t) => DropdownMenuItem<String?>(
                                  value: t.key,
                                  child: Text('${t.name} — ${t.businessType}'),
                                ),
                              ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) {
                                    if (value == null) {
                                      setState(() => _templateKey = null);
                                      return;
                                    }
                                    final template = templates.firstWhere((t) => t.key == value);
                                    _applyTemplate(template);
                                  },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextFormField(
                            initialValue: _businessType,
                            key: ValueKey(_businessType),
                            enabled: _templateKey == null && !_saving,
                            decoration: const InputDecoration(
                              labelText: 'Business Type',
                              border: OutlineInputBorder(),
                              helperText: 'Industry category.',
                            ),
                            onChanged: (v) => _businessType = v,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Owner Account Section
                    const Text(
                      '2. Owner & Admin Account',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Usernames are scoped to this business. Multiple businesses can independently have "admin".',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ownerUsernameController,
                            decoration: const InputDecoration(
                              labelText: 'Owner Username *',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: _ownerPasswordController,
                            obscureText: _hidePassword,
                            decoration: InputDecoration(
                              labelText: 'Owner Password *',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(_hidePassword ? Icons.visibility : Icons.visibility_off),
                                onPressed: () => setState(() => _hidePassword = !_hidePassword),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ownerPhoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone (optional)',
                              prefixIcon: Icon(Icons.phone_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: _ownerEmailController,
                            decoration: const InputDecoration(
                              labelText: 'Email (optional)',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 16),

                    // First Store Location & Tax Section
                    const Text(
                      '3. Initial Store Location & Tax Details',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _storeNameController,
                            decoration: const InputDecoration(
                              labelText: 'Default Store Name *',
                              hintText: 'e.g. Main / Counter 1',
                              prefixIcon: Icon(Icons.storefront_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: _storeCodeController,
                            decoration: const InputDecoration(
                              labelText: 'Store Code *',
                              hintText: 'e.g. MAIN',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: _gstinController,
                            decoration: const InputDecoration(
                              labelText: 'GSTIN (Optional)',
                              hintText: 'Non-GST businesses can leave empty',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Subscription & Division Section
                    const Text(
                      '4. Division & Subscription Plan',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _newDivision,
                      title: const Text('Make this the MAIN business of a new division'),
                      subtitle: const Text(
                        'Creates a Business Division above this company. Child businesses can be added under it later.',
                      ),
                      onChanged: _saving
                          ? null
                          : (value) => setState(() {
                              _newDivision = value;
                              if (value) {
                                _divisionId = null;
                                _divisionRole = 'main';
                              }
                            }),
                    ),
                    if (!_newDivision) ...[
                      DropdownButtonFormField<String?>(
                        initialValue: _divisionId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Parent Business Division (optional)',
                          border: OutlineInputBorder(),
                          helperText: 'Choose a division to make this a child business.',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Standalone business / no division'),
                          ),
                          ...divisions.map(
                            (d) => DropdownMenuItem<String?>(
                              value: d['division_id']?.toString(),
                              child: Text('${d['division_name']} • ${d['division_code']}'),
                            ),
                          ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => setState(() {
                                _divisionId = value;
                                _divisionRole = 'child';
                              }),
                      ),
                    ],
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String?>(
                      initialValue: _planId,
                      decoration: const InputDecoration(
                        labelText: 'Subscription Plan (Optional)',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('No plan yet / Trial'),
                        ),
                        ...plans.map(
                          (p) => DropdownMenuItem<String?>(
                            value: p.id,
                            child: Text('${p.name} — ${p.currencyCode} ${p.monthlyPrice.toStringAsFixed(0)}/month'),
                          ),
                        ),
                      ],
                      onChanged: _saving ? null : (v) => setState(() => _planId = v),
                    ),

                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Modules Section
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '5. Module Subscriptions',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text('${_selectedModules.length} selected'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ...modules.map((m) {
                      final required = m.key == 'dashboard';
                      final selected = required || _selectedModules.contains(m.key);
                      return CheckboxListTile(
                        value: selected,
                        onChanged: required || _saving
                            ? null
                            : (v) => setState(() {
                                if (v == true) {
                                  _selectedModules.add(m.key);
                                  for (final dep in m.dependencies) {
                                    _selectedModules.add(dep);
                                  }
                                } else {
                                  _selectedModules.remove(m.key);
                                }
                              }),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(m.name),
                        subtitle: Text('${m.category}${m.description == null ? '' : ' • ${m.description}'}'),
                        secondary: required ? const Chip(label: Text('Required')) : null,
                      );
                    }),

                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                          ),
                        ),
                      ),

                    const SizedBox(height: 28),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _create,
                        icon: const Icon(Icons.add_business_outlined),
                        label: Text(_saving ? 'Creating & Provisioning...' : 'Create Business & Generate Codes'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
