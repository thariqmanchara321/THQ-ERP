import 'package:flutter/material.dart';
import '../widgets/admin_home_button.dart';

import '../models/platform_models.dart';
import '../services/platform_config_service.dart';

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});
  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  final _service = PlatformConfigService();
  late Future<List<BusinessTemplate>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _service.getTemplates();
  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _open([BusinessTemplate? template]) async {
    final modules = await _service.getModules();
    if (!mounted) return;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TemplateDialog(
        service: _service,
        modules: modules,
        template: template,
      ),
    );
    if (changed == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Business Templates'),
        actions: const [AdminHomeButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('Template'),
      ),
      body: FutureBuilder<List<BusinessTemplate>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final rows = snapshot.data ?? const [];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(28),
              children: [
                const Text(
                  'Business Templates',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Reusable starting configurations for retail, restaurant, workshop, healthcare, labs and custom businesses.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                ...rows.map(
                  (t) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.dashboard_customize_outlined),
                      title: Text(
                        t.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${t.businessType}  •  ${t.moduleKeys.length} modules  •  ${t.key}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (t.isSystem) const Chip(label: Text('System')),
                          if (!t.isActive)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Chip(label: Text('Disabled')),
                            ),
                          IconButton(
                            onPressed: () => _open(t),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TemplateDialog extends StatefulWidget {
  final PlatformConfigService service;
  final List<PlatformModuleInfo> modules;
  final BusinessTemplate? template;
  const _TemplateDialog({
    required this.service,
    required this.modules,
    this.template,
  });
  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  late final TextEditingController _key;
  late final TextEditingController _name;
  late final TextEditingController _type;
  late final TextEditingController _description;
  late final TextEditingController _sort;
  late bool _active;
  late Set<String> _selected;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    _key = TextEditingController(text: t?.key ?? '');
    _name = TextEditingController(text: t?.name ?? '');
    _type = TextEditingController(text: t?.businessType ?? 'Custom');
    _description = TextEditingController(text: t?.description ?? '');
    _sort = TextEditingController(text: (t?.sortOrder ?? 100).toString());
    _active = t?.isActive ?? true;
    _selected = Set<String>.from(t?.moduleKeys ?? const ['dashboard']);
    _selected.add('dashboard');
  }

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
      await widget.service.saveTemplate(
        id: widget.template?.id,
        key: _key.text,
        name: _name.text,
        businessType: _type.text,
        description: _description.text,
        isActive: _active,
        sortOrder: int.tryParse(_sort.text) ?? 100,
        moduleKeys: _selected.toList(),
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
      title: Text(
        widget.template == null ? 'Create Template' : 'Edit Template',
      ),
      content: SizedBox(
        width: 720,
        height: 650,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _key,
                    enabled: widget.template == null,
                    decoration: const InputDecoration(
                      labelText: 'Template key',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _type,
                    decoration: const InputDecoration(
                      labelText: 'Business type',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _sort,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Sort order'),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            SwitchListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Active template'),
            ),
            const Divider(),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Modules',
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
                                  for (final dependency in m.dependencies) {
                                    _selected.add(dependency);
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
