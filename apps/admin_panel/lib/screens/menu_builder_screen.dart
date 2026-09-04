import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/business.dart';
import '../services/business_service.dart';
import '../services/platform_config_service.dart';
import '../widgets/admin_home_button.dart';

class MenuBuilderScreen extends StatefulWidget {
  const MenuBuilderScreen({super.key});

  @override
  State<MenuBuilderScreen> createState() => _MenuBuilderScreenState();
}

class _MenuBuilderScreenState extends State<MenuBuilderScreen> {
  final BusinessService _businessService = BusinessService();
  final PlatformConfigService _service = PlatformConfigService();

  List<Business> _businesses = const [];
  List<Map<String, dynamic>> _nodes = const [];
  List<dynamic> _modules = const [];
  String? _tenantId;
  String _app = 'client';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait([
        _businessService.getBusinesses(),
        _service.getModules(),
      ]);
      _businesses = results[0] as List<Business>;
      _modules = results[1] as List<dynamic>;
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.getMenuNodes(
        tenantId: _tenantId,
        appKey: _app,
      );
      if (mounted) setState(() => _nodes = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyDefault() async {
    if (_tenantId == null) return;
    try {
      await _service.copyDefaultMenu(tenantId: _tenantId!, appKey: _app);
      await _load();
      _msg(
        'Default $_app menu copied. This business can now be customized independently.',
      );
    } catch (error) {
      _msg(error.toString());
    }
  }

  int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 100;

  List<Map<String, dynamic>> _children(String? parentId) {
    final rows = _nodes
        .where((row) => row['parent_id']?.toString() == parentId)
        .toList();
    rows.sort((a, b) => _int(a['sort_order']).compareTo(_int(b['sort_order'])));
    return rows;
  }

  String _moduleName(String key) {
    for (final module in _modules) {
      try {
        if (module.key.toString() == key) return module.name.toString();
      } catch (_) {}
    }
    return key;
  }

  Map<String, dynamic> _metadata(Map<String, dynamic>? node) {
    final raw = node?['metadata'];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  Future<void> _edit([
    Map<String, dynamic>? node,
    String? initialParent,
  ]) async {
    final isNew = node == null;
    var type = node?['node_type']?.toString() ?? 'module';
    final label = TextEditingController(text: node?['label']?.toString() ?? '');
    final key = TextEditingController(
      text: node?['node_key']?.toString() ?? '',
    );
    final icon = TextEditingController(
      text: node?['icon_key']?.toString() ?? '',
    );
    final sort = TextEditingController(text: '${node?['sort_order'] ?? 100}');
    final metadata = _metadata(node);
    final roles = TextEditingController(
      text: (metadata['roles'] as List? ?? const [])
          .map((e) => e.toString())
          .join(', '),
    );
    final permissions = TextEditingController(
      text: (metadata['permissions'] as List? ?? const [])
          .map((e) => e.toString())
          .join(', '),
    );
    var moduleKey = node?['module_key']?.toString();
    var parent = node?['parent_id']?.toString() ?? initialParent;
    var enabled = node?['enabled'] != false;
    var collapsed = node?['collapsed_by_default'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(isNew ? 'Add Menu / Group' : 'Edit Menu / Group'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'group',
                        label: Text('Group / Dropdown'),
                        icon: Icon(Icons.folder_outlined),
                      ),
                      ButtonSegment(
                        value: 'module',
                        label: Text('Module / Menu'),
                        icon: Icon(Icons.extension_outlined),
                      ),
                    ],
                    selected: {type},
                    onSelectionChanged: (value) => setLocal(() {
                      type = value.first;
                      if (type == 'group') moduleKey = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: label,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: key,
                          decoration: const InputDecoration(
                            labelText: 'Stable menu key',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (type == 'module')
                    DropdownButtonFormField<String>(
                      initialValue: moduleKey,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Feature / module',
                      ),
                      items: _modules
                          .map(
                            (module) => DropdownMenuItem<String>(
                              value: module.key.toString(),
                              child: Text('${module.name} (${module.key})'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setLocal(() => moduleKey = value),
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: parent,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Parent menu / dropdown',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Top level'),
                      ),
                      ..._nodes
                          .where(
                            (row) =>
                                row['id']?.toString() !=
                                node?['id']?.toString(),
                          )
                          .map(
                            (parentNode) => DropdownMenuItem<String?>(
                              value: parentNode['id']?.toString(),
                              child: Text(
                                '${parentNode['node_type'] == 'group' ? '[Group]' : '[Menu]'} ${parentNode['label'] ?? ''}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                    ],
                    onChanged: (value) => setLocal(() => parent = value),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: icon,
                          decoration: const InputDecoration(
                            labelText: 'Icon key',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: sort,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Order'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: roles,
                    decoration: const InputDecoration(
                      labelText: 'Visible only for roles (optional)',
                      hintText: 'owner, manager, cashier',
                      helperText:
                          'Comma-separated. Empty = all roles allowed by normal module permissions.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: permissions,
                    decoration: const InputDecoration(
                      labelText: 'Extra permission filter (optional)',
                      hintText: 'settings.manage, sales.manage',
                      helperText:
                          'At least one listed permission must match. Empty = normal module permissions only.',
                    ),
                  ),
                  SwitchListTile(
                    dense: true,
                    value: enabled,
                    onChanged: (value) => setLocal(() => enabled = value),
                    title: const Text('Visible / enabled'),
                  ),
                  if (type == 'group')
                    SwitchListTile(
                      dense: true,
                      value: collapsed,
                      onChanged: (value) => setLocal(() => collapsed = value),
                      title: const Text('Collapsed by default'),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      try {
        List<String> values(TextEditingController controller) => controller.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
        await _service.saveMenuNode(
          id: node?['id']?.toString(),
          tenantId: _tenantId,
          appKey: _app,
          nodeKey: key.text.trim().isEmpty
              ? 'menu_${DateTime.now().millisecondsSinceEpoch}'
              : key.text.trim(),
          nodeType: type,
          moduleKey: moduleKey,
          parentId: parent,
          label: label.text,
          iconKey: icon.text,
          sortOrder: int.tryParse(sort.text) ?? 100,
          enabled: enabled,
          collapsedByDefault: collapsed,
          metadata: {
            ...metadata,
            'roles': values(roles),
            'permissions': values(permissions),
          },
        );
        await _load();
        _msg('Menu updated.');
      } catch (error) {
        _msg(error.toString());
      }
    }
    label.dispose();
    key.dispose();
    icon.dispose();
    sort.dispose();
    roles.dispose();
    permissions.dispose();
  }

  Future<void> _delete(Map<String, dynamic> node) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${node['label']}?'),
        content: const Text(
          'Nested menu items are removed from this layout too. ERP modules and business data are never deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteMenuNode(node['id'].toString());
      await _load();
    } catch (error) {
      _msg(error.toString());
    }
  }

  void _msg(String text) {
    if (mounted) {
      ThqNotify.showSnackBar(context, SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 42,
      title: const Text('THQ Menu Builder'),
      actions: const [AdminHomeButton()],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _loading ? null : () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('Menu / Group'),
    ),
    body: Padding(
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dynamic Client & POS Navigation',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
          const Text(
            'Rename, nest, reorder, hide and role-filter menu groups without changing stable feature IDs.',
            style: TextStyle(fontSize: 10.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 330,
                child: DropdownButtonFormField<String?>(
                  initialValue: _tenantId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Menu scope'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('GLOBAL DEFAULT'),
                    ),
                    ..._businesses.map(
                      (business) => DropdownMenuItem<String?>(
                        value: business.id,
                        child: Text(business.name),
                      ),
                    ),
                  ],
                  onChanged: (value) async {
                    setState(() => _tenantId = value);
                    await _load();
                  },
                ),
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'client', label: Text('THQ Business')),
                  ButtonSegment(value: 'pos', label: Text('THQ POS')),
                ],
                selected: {_app},
                onSelectionChanged: (value) async {
                  setState(() => _app = value.first);
                  await _load();
                },
              ),
              if (_tenantId != null)
                OutlinedButton.icon(
                  onPressed: _copyDefault,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copy Global Layout'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _nodes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No menu layout found.'),
                        if (_tenantId != null)
                          TextButton(
                            onPressed: _copyDefault,
                            child: const Text(
                              'Copy global menu to start editing',
                            ),
                          ),
                      ],
                    ),
                  )
                : ListView(
                    children: _children(
                      null,
                    ).map((node) => _nodeCard(node, 0)).toList(),
                  ),
          ),
        ],
      ),
    ),
  );

  Widget _nodeCard(Map<String, dynamic> node, int depth) {
    final isGroup = node['node_type'] == 'group';
    final children = _children(node['id']?.toString());
    final metadata = _metadata(node);
    final roles = (metadata['roles'] as List? ?? const []).join(', ');
    final permissions = (metadata['permissions'] as List? ?? const []).join(
      ', ',
    );
    final subtitle = isGroup
        ? 'Dropdown/group • ${children.length} children • order ${node['sort_order']}'
        : '${_moduleName(node['module_key']?.toString() ?? '')} • ${node['module_key']} • order ${node['sort_order']}';
    return Padding(
      padding: EdgeInsets.only(left: depth * 18.0, bottom: 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: ExpansionTile(
          initiallyExpanded: true,
          controlAffinity: ListTileControlAffinity.leading,
          leading: Icon(
            isGroup ? Icons.folder_open_outlined : Icons.extension_outlined,
            size: 19,
          ),
          title: Text(
            node['label']?.toString() ?? '',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
          subtitle: Text(
            [
              subtitle,
              if (roles.isNotEmpty) 'roles: $roles',
              if (permissions.isNotEmpty) 'permission: $permissions',
            ].join(' • '),
            style: const TextStyle(fontSize: 9.5),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isGroup)
                IconButton(
                  onPressed: () => _edit(null, node['id']?.toString()),
                  tooltip: 'Add inside',
                  icon: const Icon(Icons.add, size: 18),
                ),
              IconButton(
                onPressed: () => _edit(node),
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                onPressed: () => _delete(node),
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
          children: children
              .map((child) => _nodeCard(child, depth + 1))
              .toList(),
        ),
      ),
    );
  }
}
