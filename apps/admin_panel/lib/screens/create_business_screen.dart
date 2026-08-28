import 'package:flutter/material.dart';
import '../widgets/admin_home_button.dart';

import '../models/platform_models.dart';
import '../services/business_service.dart';
import '../services/platform_config_service.dart';

class CreateBusinessScreen extends StatefulWidget {
  const CreateBusinessScreen({super.key});
  @override
  State<CreateBusinessScreen> createState() => _CreateBusinessScreenState();
}

class _CreateBusinessScreenState extends State<CreateBusinessScreen> {
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _businessService = BusinessService();
  final _platformService = PlatformConfigService();

  late Future<
    (
      List<PlatformModuleInfo>,
      List<BusinessTemplate>,
      List<SubscriptionPlan>,
      List<Map<String, dynamic>>,
    )
  >
  _future;
  final Set<String> _selectedModules = {'dashboard'};
  String _businessType = 'General Retail';
  String? _templateKey;
  String? _planId;
  String? _divisionId;
  bool _newDivision = false;
  String _divisionRole = 'child';
  bool _slugEditedManually = false;
  bool _saving = false;
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
  >
  _load() async {
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
    final slug = _slugController.text.trim();
    if (name.isEmpty || slug.isEmpty) {
      setState(
        () => _error = name.isEmpty
            ? 'Business name is required.'
            : 'Business slug is required.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final tenantId = await _businessService.createBusiness(
        name: name,
        slug: slug,
        businessType: _businessType,
        moduleKeys: _selectedModules.toList(),
      );
      if (_templateKey != null) {
        await _businessService.applyTemplateSettings(
          tenantId: tenantId,
          templateKey: _templateKey!,
        );
      }
      if (_planId != null) {
        await _platformService.setTenantSubscription(
          tenantId: tenantId,
          planId: _planId!,
          status: 'trial',
          billingCycle: 'monthly',
        );
      }
      if (_newDivision) {
        final divisionId = await _businessService.saveDivision(
          name: '$name Division',
        );
        await _businessService.assignBusinessToDivision(
          tenantId: tenantId,
          divisionId: divisionId,
          memberType: 'main',
        );
      } else if (_divisionId != null) {
        await _businessService.assignBusinessToDivision(
          tenantId: tenantId,
          divisionId: _divisionId!,
          memberType: _divisionRole,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_updateSlug);
    _nameController.dispose();
    _slugController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Create Business',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: const [AdminHomeButton()],
      ),
      body:
          FutureBuilder<
            (
              List<PlatformModuleInfo>,
              List<BusinessTemplate>,
              List<SubscriptionPlan>,
              List<Map<String, dynamic>>,
            )
          >(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text(snapshot.error.toString()));
              }
              final data = snapshot.data!;
              final modules = data.$1;
              final templates = data.$2.where((t) => t.isActive).toList();
              final plans = data.$3.where((p) => p.isActive).toList();
              final divisions = data.$4
                  .where((d) => d['active'] != false)
                  .toList();
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Container(
                    width: 900,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Business Details',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Business Name',
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
                                  labelText: 'Business ID / Slug',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String?>(
                          initialValue: _templateKey,
                          decoration: const InputDecoration(
                            labelText: 'Business Template',
                            border: OutlineInputBorder(),
                            helperText:
                                'A template preselects modules and default settings; the tenant can still be customized.',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Custom / no template'),
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
                                  final template = templates.firstWhere(
                                    (t) => t.key == value,
                                  );
                                  _applyTemplate(template);
                                },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: _businessType,
                          key: ValueKey(_businessType),
                          enabled: _templateKey == null && !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Business Type',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => _businessType = v,
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _newDivision,
                          title: const Text(
                            'Make this the MAIN business of a new division',
                          ),
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
                              helperText:
                                  'Choose a division to make this a child business. Stores/POS remain locations under this business.',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  'Standalone business / no division',
                                ),
                              ),
                              ...divisions.map(
                                (d) => DropdownMenuItem<String?>(
                                  value: d['division_id']?.toString(),
                                  child: Text(
                                    '${d['division_name']} • ${d['division_code']}',
                                  ),
                                ),
                              ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) => setState(() {
                                    _divisionId = value;
                                    _divisionRole = value == null
                                        ? 'child'
                                        : 'child';
                                  }),
                          ),
                          if (_divisionId != null) ...[
                            const SizedBox(height: 12),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'child',
                                  label: Text('Child business'),
                                  icon: Icon(Icons.account_tree_outlined),
                                ),
                                ButtonSegment(
                                  value: 'main',
                                  label: Text('Make main'),
                                  icon: Icon(Icons.corporate_fare_outlined),
                                ),
                              ],
                              selected: {_divisionRole},
                              onSelectionChanged: _saving
                                  ? null
                                  : (v) =>
                                        setState(() => _divisionRole = v.first),
                            ),
                          ],
                        ],
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String?>(
                          initialValue: _planId,
                          decoration: const InputDecoration(
                            labelText: 'Subscription Plan',
                            border: OutlineInputBorder(),
                            helperText:
                                'Optional now; can be assigned later from Business → Subscription.',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('No plan yet'),
                            ),
                            ...plans.map(
                              (p) => DropdownMenuItem<String?>(
                                value: p.id,
                                child: Text(
                                  '${p.name} — ${p.currencyCode} ${p.monthlyPrice.toStringAsFixed(0)}/month',
                                ),
                              ),
                            ),
                          ],
                          onChanged: _saving
                              ? null
                              : (v) {
                                  setState(() {
                                    _planId = v;
                                    if (v != null) {
                                      final plan = plans.firstWhere(
                                        (p) => p.id == v,
                                      );
                                      _selectedModules.removeWhere(
                                        (key) =>
                                            key != 'dashboard' &&
                                            !plan.moduleKeys.contains(key),
                                      );
                                    }
                                  });
                                },
                        ),
                        const SizedBox(height: 28),
                        const Divider(),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Modules',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text('${_selectedModules.length} selected'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Modules can be customized after applying a template. Dashboard is always required.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 14),
                        ...modules.map((m) {
                          final required = m.key == 'dashboard';
                          final selectedPlan = _planId == null
                              ? null
                              : plans.firstWhere((p) => p.id == _planId);
                          final entitled =
                              selectedPlan == null ||
                              selectedPlan.moduleKeys.contains(m.key) ||
                              required;
                          final selected =
                              required || _selectedModules.contains(m.key);
                          return CheckboxListTile(
                            value: selected,
                            onChanged: required || _saving || !entitled
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
                            subtitle: Text(
                              '${m.category}${m.description == null ? '' : ' • ${m.description}'}',
                            ),
                            secondary: required
                                ? const Chip(label: Text('Required'))
                                : (!entitled
                                      ? const Chip(label: Text('Not in plan'))
                                      : (m.isCore
                                            ? const Chip(label: Text('Core'))
                                            : null)),
                          );
                        }),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _create,
                            icon: const Icon(Icons.add_business_outlined),
                            label: Text(
                              _saving ? 'Creating...' : 'Create Business',
                            ),
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
