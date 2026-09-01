import 'package:flutter/material.dart';
import '../widgets/admin_home_button.dart';

import '../models/platform_models.dart';
import '../services/platform_config_service.dart';

class SubscriptionPlansScreen extends StatefulWidget {
  const SubscriptionPlansScreen({super.key});
  @override
  State<SubscriptionPlansScreen> createState() =>
      _SubscriptionPlansScreenState();
}

class _SubscriptionPlansScreenState extends State<SubscriptionPlansScreen> {
  final _service = PlatformConfigService();
  late Future<List<SubscriptionPlan>> _future;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _service.getPlans();
  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _open([SubscriptionPlan? plan]) async {
    final modules = await _service.getModules();
    if (!mounted) return;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _PlanDialog(service: _service, modules: modules, plan: plan),
    );
    if (changed == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Subscription Plans'),
        actions: const [AdminHomeButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('Plan'),
      ),
      body: FutureBuilder<List<SubscriptionPlan>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final plans = snapshot.data ?? const [];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(28),
              children: [
                const Text(
                  'Subscription Plans',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Plans control commercial entitlements and usage limits; tenant modules and user permissions remain separate controls.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: plans
                      .map(
                        (p) => SizedBox(
                          width: 340,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          p.name,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => _open(p),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    p.description ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    '${p.currencyCode} ${p.monthlyPrice.toStringAsFixed(0)} / month',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${p.moduleKeys.length} modules • ${p.limits['max_users'] ?? '∞'} users',
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: p.moduleKeys
                                        .take(6)
                                        .map((m) => Chip(label: Text(m)))
                                        .toList(),
                                  ),
                                  if (!p.isActive)
                                    const Chip(label: Text('Disabled')),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PlanDialog extends StatefulWidget {
  final PlatformConfigService service;
  final List<PlatformModuleInfo> modules;
  final SubscriptionPlan? plan;
  const _PlanDialog({required this.service, required this.modules, this.plan});
  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  late final TextEditingController _key,
      _name,
      _description,
      _monthly,
      _yearly,
      _currency,
      _sort,
      _maxUsers,
      _maxLocations,
      _maxProducts,
      _maxInvoices;
  late bool _active;
  late Set<String> _selected;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _key = TextEditingController(text: p?.key ?? '');
    _name = TextEditingController(text: p?.name ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _monthly = TextEditingController(text: (p?.monthlyPrice ?? 0).toString());
    _yearly = TextEditingController(text: (p?.yearlyPrice ?? 0).toString());
    _currency = TextEditingController(text: p?.currencyCode ?? 'INR');
    _sort = TextEditingController(text: (p?.sortOrder ?? 100).toString());
    _maxUsers = TextEditingController(text: '${p?.limits['max_users'] ?? 5}');
    _maxLocations = TextEditingController(
      text: '${p?.limits['max_locations'] ?? 1}',
    );
    _maxProducts = TextEditingController(
      text: '${p?.limits['max_products'] ?? 1000}',
    );
    _maxInvoices = TextEditingController(
      text: '${p?.limits['max_invoices_per_month'] ?? 1000}',
    );
    _active = p?.isActive ?? true;
    _selected = Set<String>.from(p?.moduleKeys ?? const ['dashboard']);
    _selected.add('dashboard');
    _normalizeCompanionModules();
  }

  bool _moduleExists(String key) => widget.modules.any((m) => m.key == key);

  void _normalizeCompanionModules() {
    if (_selected.contains('sales') && _moduleExists('sales_details')) {
      _selected.add('sales_details');
    }
    if (_selected.contains('purchases') && _moduleExists('purchase_details')) {
      _selected.add('purchase_details');
    }
  }

  bool _isRequiredCompanion(String key) =>
      (key == 'sales_details' && _selected.contains('sales')) ||
      (key == 'purchase_details' && _selected.contains('purchases'));

  void _addModule(String key) {
    final module = widget.modules.firstWhere((m) => m.key == key);
    setState(() {
      _selected.add(module.key);
      for (final dep in module.dependencies) {
        _selected.add(dep);
      }
      _normalizeCompanionModules();
    });
  }

  void _removeModule(String key) {
    if (key == 'dashboard' || _isRequiredCompanion(key)) return;
    setState(() {
      _selected.remove(key);
      if (key == 'sales') _selected.remove('sales_details');
      if (key == 'purchases') _selected.remove('purchase_details');
    });
  }

  int _int(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;
  double _double(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    if (_key.text.trim().isEmpty || _name.text.trim().isEmpty) {
      setState(() => _error = 'Key and name are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.savePlan(
        id: widget.plan?.id,
        key: _key.text,
        name: _name.text,
        description: _description.text,
        monthlyPrice: _double(_monthly),
        yearlyPrice: _double(_yearly),
        currencyCode: _currency.text,
        isActive: _active,
        sortOrder: _int(_sort, 100),
        moduleKeys: _selected.toList(),
        limits: {
          'max_users': _int(_maxUsers, 5),
          'max_locations': _int(_maxLocations, 1),
          'max_products': _int(_maxProducts, 1000),
          'max_invoices_per_month': _int(_maxInvoices, 1000),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.plan == null ? 'Create Plan' : 'Edit Plan'),
      content: SizedBox(
        width: 760,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _key,
                    enabled: widget.plan == null,
                    decoration: const InputDecoration(labelText: 'Plan key'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Plan name'),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _monthly,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Monthly price',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _yearly,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Yearly price',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _currency,
                    decoration: const InputDecoration(labelText: 'Currency'),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _maxUsers,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Max users'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _maxLocations,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Max locations',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _maxProducts,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Max products',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _maxInvoices,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Invoices/month',
                    ),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Active plan'),
            ),
            const Divider(),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Entitled modules', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('module-picker-${_selected.length}'),
              initialValue: null,
              decoration: const InputDecoration(
                labelText: 'Add module',
                hintText: 'Choose a module',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.extension_outlined),
              ),
              items: widget.modules
                  .where((m) => m.isActive && !_selected.contains(m.key))
                  .map((m) => DropdownMenuItem<String>(
                        value: m.key,
                        child: Text('${m.name}  •  ${m.category}'),
                      ))
                  .toList(),
              onChanged: (key) {
                if (key != null) _addModule(key);
              },
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selected.map((key) {
                      final matches = widget.modules.where((m) => m.key == key);
                      final label = matches.isEmpty ? key : matches.first.name;
                      return InputChip(
                        avatar: key == 'dashboard'
                            ? const Icon(Icons.lock_outline, size: 16)
                            : null,
                        label: Text(label),
                        onDeleted: key == 'dashboard' || _isRequiredCompanion(key)
                            ? null
                            : () => _removeModule(key),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}
