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
      title: Text(widget.plan == null ? 'Create Plan' : 'Edit Plan'),
      content: SizedBox(
        width: 760,
        height: 690,
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
              child: Text(
                'Entitled modules',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView(
                children: widget.modules
                    .where((m) => m.isActive)
                    .map(
                      (m) => CheckboxListTile(
                        dense: true,
                        value:
                            _selected.contains(m.key) || m.key == 'dashboard',
                        onChanged: m.key == 'dashboard'
                            ? null
                            : (v) => setState(() {
                                if (v == true) {
                                  _selected.add(m.key);
                                  for (final dep in m.dependencies) {
                                    _selected.add(dep);
                                  }
                                } else {
                                  _selected.remove(m.key);
                                }
                              }),
                        title: Text(m.name),
                        subtitle: Text('${m.category} • ${m.key}'),
                      ),
                    )
                    .toList(),
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
