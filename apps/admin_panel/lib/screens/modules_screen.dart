import 'package:flutter/material.dart';
import '../widgets/admin_home_button.dart';
import 'menu_builder_screen.dart';

import '../models/platform_models.dart';
import '../services/platform_config_service.dart';

class ModulesScreen extends StatefulWidget {
  const ModulesScreen({super.key});

  @override
  State<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends State<ModulesScreen> {
  final _service = PlatformConfigService();
  late Future<List<PlatformModuleInfo>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _service.getModules();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _edit([PlatformModuleInfo? module]) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ModuleDialog(module: module, service: _service),
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: const Text('Module Catalogue'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MenuBuilderScreen()),
            ),
            icon: const Icon(Icons.account_tree_outlined),
            label: const Text('Menu Builder'),
          ),
          const AdminHomeButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Module'),
      ),
      body: FutureBuilder<List<PlatformModuleInfo>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Error(message: snapshot.error.toString(), retry: _refresh);
          }
          final modules = snapshot.data ?? const [];
          final groups = <String, List<PlatformModuleInfo>>{};
          for (final module in modules) {
            groups.putIfAbsent(module.category, () => []).add(module);
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(6),
              children: [
                const Text(
                  'Module Catalogue',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Control core, POS and industry modules, dependencies and availability.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 6),
                ...groups.entries.map(
                  (entry) => _Group(
                    title: entry.key,
                    modules: entry.value,
                    onEdit: _edit,
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

class _Group extends StatelessWidget {
  final String title;
  final List<PlatformModuleInfo> modules;
  final Future<void> Function(PlatformModuleInfo) onEdit;

  const _Group({
    required this.title,
    required this.modules,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            ...modules.map(
              (module) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  module.isActive
                      ? Icons.extension_outlined
                      : Icons.extension_off_outlined,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        module.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (module.isCore)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Chip(label: Text('Core')),
                      ),
                    if (module.isBeta)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Chip(label: Text('Beta')),
                      ),
                    if (!module.isActive)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Chip(label: Text('Disabled')),
                      ),
                  ],
                ),
                subtitle: Text(
                  '${module.key}${module.dependencies.isEmpty ? '' : '  •  requires: ${module.dependencies.join(', ')}'}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => onEdit(module),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleDialog extends StatefulWidget {
  final PlatformModuleInfo? module;
  final PlatformConfigService service;
  const _ModuleDialog({required this.module, required this.service});

  @override
  State<_ModuleDialog> createState() => _ModuleDialogState();
}

class _ModuleDialogState extends State<_ModuleDialog> {
  late final TextEditingController _key;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _sortOrder;
  late final TextEditingController _minimumPlan;
  late final TextEditingController _dependencies;
  late final TextEditingController _businessTypes;
  late bool _core;
  late bool _active;
  late bool _beta;
  late bool _requiresConfig;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final m = widget.module;
    _key = TextEditingController(text: m?.key ?? '');
    _name = TextEditingController(text: m?.name ?? '');
    _description = TextEditingController(text: m?.description ?? '');
    _category = TextEditingController(text: m?.category ?? 'General');
    _sortOrder = TextEditingController(text: (m?.sortOrder ?? 100).toString());
    _minimumPlan = TextEditingController(text: m?.minimumPlanKey ?? '');
    _dependencies = TextEditingController(
      text: (m?.dependencies ?? const <String>[]).join(', '),
    );
    _businessTypes = TextEditingController(
      text: (m?.businessTypes ?? const <String>[]).join(', '),
    );
    _core = m?.isCore ?? false;
    _active = m?.isActive ?? true;
    _beta = m?.isBeta ?? false;
    _requiresConfig = m?.requiresConfiguration ?? false;
  }

  List<String> _csv(String value) =>
      value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.saveModule(
        key: _key.text,
        name: _name.text,
        description: _description.text,
        category: _category.text,
        sortOrder: int.tryParse(_sortOrder.text) ?? 100,
        isCore: _core,
        isActive: _active,
        isBeta: _beta,
        requiresConfiguration: _requiresConfig,
        minimumPlanKey: _minimumPlan.text.trim().isEmpty
            ? null
            : _minimumPlan.text.trim(),
        dependencies: _csv(_dependencies.text),
        businessTypes: _csv(_businessTypes.text),
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
      title: Text(
        widget.module == null
            ? 'Create Module'
            : 'Module: ${widget.module!.key}',
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _key,
                enabled: widget.module == null,
                decoration: const InputDecoration(labelText: 'Module key'),
              ),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              TextField(
                controller: _category,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              TextField(
                controller: _sortOrder,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sort order'),
              ),
              TextField(
                controller: _minimumPlan,
                decoration: const InputDecoration(
                  labelText: 'Minimum plan key (optional)',
                ),
              ),
              TextField(
                controller: _dependencies,
                decoration: const InputDecoration(
                  labelText: 'Dependencies (comma separated)',
                ),
              ),
              TextField(
                controller: _businessTypes,
                decoration: const InputDecoration(
                  labelText: 'Recommended business types (comma separated)',
                ),
              ),
              SwitchListTile(
                value: _core,
                onChanged: (v) => setState(() => _core = v),
                title: const Text('Core module'),
              ),
              SwitchListTile(
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Active'),
              ),
              SwitchListTile(
                value: _beta,
                onChanged: (v) => setState(() => _beta = v),
                title: const Text('Beta'),
              ),
              SwitchListTile(
                value: _requiresConfig,
                onChanged: (v) => setState(() => _requiresConfig = v),
                title: const Text('Requires configuration'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
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

class _Error extends StatelessWidget {
  final String message;
  final Future<void> Function() retry;
  const _Error({required this.message, required this.retry});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        OutlinedButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  );
}
