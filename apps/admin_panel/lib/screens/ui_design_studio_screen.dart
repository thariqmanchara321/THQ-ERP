import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/business.dart';
import '../services/business_service.dart';
import '../services/platform_config_service.dart';
import '../widgets/admin_home_button.dart';

class UiDesignStudioScreen extends StatefulWidget {
  const UiDesignStudioScreen({super.key});

  @override
  State<UiDesignStudioScreen> createState() => _UiDesignStudioScreenState();
}

class _UiDesignStudioScreenState extends State<UiDesignStudioScreen>
    with SingleTickerProviderStateMixin {
  final _service = PlatformConfigService();
  final _businessService = BusinessService();
  late TabController _tabs;
  late Future<List<Map<String, dynamic>>> _templates;
  late Future<List<Business>> _businesses;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _reload();
  }

  void _reload() {
    _templates = _service.getUiDesignTemplates();
    _businesses = _businessService.getBusinesses();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _editTemplate([Map<String, dynamic>? row]) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DesignTemplateDialog(service: _service, template: row),
    );
    if (changed == true && mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: const Text(
          'Design Studio',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [AdminHomeButton()],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Design Templates'),
            Tab(text: 'Business Branding'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _templates,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.all(6),
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'UI templates',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Reusable Client and POS themes. Change colors, spacing and POS layout without rebuilding the apps.',
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _editTemplate(),
                        icon: const Icon(Icons.add),
                        label: const Text('New template'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: rows
                        .map(
                          (r) => _TemplatePreviewCard(
                            row: r,
                            onEdit: () => _editTemplate(r),
                          ),
                        )
                        .toList(),
                  ),
                ],
              );
            },
          ),
          FutureBuilder<List<Object>>(
            future: Future.wait<Object>([_businesses, _templates]),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final businesses = snapshot.data![0] as List<Business>;
              final templates = snapshot.data![1] as List<Map<String, dynamic>>;
              return _BusinessBrandingPanel(
                service: _service,
                businesses: businesses,
                templates: templates,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TemplatePreviewCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onEdit;
  const _TemplatePreviewCard({required this.row, required this.onEdit});

  Color _color(String key, Color fallback) {
    final c = row['config'] is Map
        ? Map<String, dynamic>.from(row['config'] as Map)
        : <String, dynamic>{};
    var value = c[key]?.toString().replaceAll('#', '') ?? '';
    if (value.length == 6) value = 'FF$value';
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final primary = _color('primary', Colors.indigo);
    final bg = _color('background', const Color(0xFFF5F5FA));
    final surface = _color('surface', Colors.white);
    final app = row['app_key']?.toString() ?? 'client';
    return SizedBox(
      width: 330,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEdit,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 150,
                color: bg,
                padding: const EdgeInsets.all(7),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 4),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: primary,
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                          const SizedBox(height: 4),
                          for (var i = 0; i < 4; i++)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              width: 28,
                              height: 5,
                              decoration: BoxDecoration(
                                color: primary.withValues(
                                  alpha: i == 0 ? .55 : .12,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            height: 26,
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                          const SizedBox(height: 9),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          height: 26,
                                          decoration: BoxDecoration(
                                            color: primary.withValues(
                                              alpha: .13,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Container(
                                          height: 26,
                                          decoration: BoxDecoration(
                                            color: primary.withValues(
                                              alpha: .08,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.bottomLeft,
                                      child: Container(
                                        width: double.infinity,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: primary.withValues(alpha: .16),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row['name']?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Chip(label: Text(app.toUpperCase())),
                      ],
                    ),
                    Text(
                      row['description']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (final key in const [
                          'primary',
                          'secondary',
                          'accent',
                          'background',
                        ]) ...[
                          Container(
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: _color(key, Colors.grey),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black12),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (row['is_default'] == true)
                          const Chip(label: Text('Default')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesignTemplateDialog extends StatefulWidget {
  final PlatformConfigService service;
  final Map<String, dynamic>? template;
  const _DesignTemplateDialog({required this.service, this.template});
  @override
  State<_DesignTemplateDialog> createState() => _DesignTemplateDialogState();
}

class _DesignTemplateDialogState extends State<_DesignTemplateDialog> {
  late final Map<String, TextEditingController> c;
  late String appKey;
  late String density;
  late String posLayout;
  late bool active;
  late bool isDefault;
  late bool gradient;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final t = widget.template ?? <String, dynamic>{};
    final config = t['config'] is Map
        ? Map<String, dynamic>.from(t['config'] as Map)
        : <String, dynamic>{};
    String v(String k, String f) =>
        (k.startsWith('cfg.') ? config[k.substring(4)] : t[k])?.toString() ?? f;
    c = {
      'key': TextEditingController(text: v('key', '')),
      'name': TextEditingController(text: v('name', '')),
      'description': TextEditingController(text: v('description', '')),
      'primary': TextEditingController(text: v('cfg.primary', '#6C5CE7')),
      'secondary': TextEditingController(text: v('cfg.secondary', '#AFA4F5')),
      'accent': TextEditingController(text: v('cfg.accent', '#7C6CF2')),
      'background': TextEditingController(text: v('cfg.background', '#F5F3FF')),
      'surface': TextEditingController(text: v('cfg.surface', '#FFFFFF')),
      'sidebar': TextEditingController(text: v('cfg.sidebar', '#FBFAFF')),
      'border': TextEditingController(text: v('cfg.border', '#E9E5F6')),
      'radius': TextEditingController(text: v('cfg.radius', '18')),
      'cartWidth': TextEditingController(text: v('cfg.pos_cart_width', '380')),
      'sort': TextEditingController(text: v('sort_order', '100')),
    };
    appKey = v('app_key', 'client');
    density = v('cfg.density', 'comfortable');
    posLayout = v('cfg.pos_layout', 'retail_grid');
    active = t['is_active'] != false;
    isDefault = t['is_default'] == true;
    gradient = config['gradient'] == true;
  }

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (c['key']!.text.trim().isEmpty || c['name']!.text.trim().isEmpty) {
      setState(() => error = 'Key and name are required.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.service.saveUiDesignTemplate(
        id: widget.template?['id']?.toString(),
        key: c['key']!.text,
        name: c['name']!.text,
        appKey: appKey,
        description: c['description']!.text,
        isActive: active,
        isDefault: isDefault,
        sortOrder: int.tryParse(c['sort']!.text) ?? 100,
        config: {
          'primary': c['primary']!.text.trim(),
          'secondary': c['secondary']!.text.trim(),
          'accent': c['accent']!.text.trim(),
          'background': c['background']!.text.trim(),
          'surface': c['surface']!.text.trim(),
          'sidebar': c['sidebar']!.text.trim(),
          'border': c['border']!.text.trim(),
          'success': '#22A06B',
          'warning': '#E6A700',
          'danger': '#E05252',
          'radius': double.tryParse(c['radius']!.text) ?? 18,
          'density': density,
          'card_style': 'soft',
          'sidebar_style': 'floating',
          'gradient': gradient,
          if (appKey == 'pos') 'pos_layout': posLayout,
          if (appKey == 'pos') 'pos_product_style': 'soft_cards',
          if (appKey == 'pos')
            'pos_cart_width': double.tryParse(c['cartWidth']!.text) ?? 380,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String key, String label, {double width = 180}) => SizedBox(
      width: width,
      child: TextField(
        controller: c[key],
        decoration: InputDecoration(labelText: label),
      ),
    );
    return AlertDialog(
      title: Text(
        widget.template == null ? 'New UI template' : 'Edit UI template',
      ),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: c['key'],
                      enabled: widget.template == null,
                      decoration: const InputDecoration(
                        labelText: 'Template key',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: c['name'],
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: c['description'],
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: appKey,
                      decoration: const InputDecoration(labelText: 'App'),
                      items: const [
                        DropdownMenuItem(
                          value: 'client',
                          child: Text('Client ERP'),
                        ),
                        DropdownMenuItem(value: 'pos', child: Text('POS')),
                      ],
                      onChanged: widget.template == null
                          ? (v) => setState(() => appKey = v!)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  field('sort', 'Sort', width: 120),
                  const SizedBox(width: 10),
                  field('radius', 'Radius', width: 120),
                ],
              ),
              const SizedBox(height: 5),
              const Text(
                'Color pattern',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  field('primary', 'Primary'),
                  field('secondary', 'Secondary'),
                  field('accent', 'Accent'),
                  field('background', 'Background'),
                  field('surface', 'Surface'),
                  field('sidebar', 'Sidebar'),
                  field('border', 'Border'),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: density,
                      decoration: const InputDecoration(labelText: 'Density'),
                      items: const [
                        DropdownMenuItem(
                          value: 'comfortable',
                          child: Text('Comfortable'),
                        ),
                        DropdownMenuItem(
                          value: 'compact',
                          child: Text('Compact'),
                        ),
                      ],
                      onChanged: (v) => setState(() => density = v!),
                    ),
                  ),
                  if (appKey == 'pos') ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: posLayout,
                        decoration: const InputDecoration(
                          labelText: 'POS layout',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'retail_grid',
                            child: Text('Retail Grid'),
                          ),
                          DropdownMenuItem(
                            value: 'compact_grid',
                            child: Text('Compact Grid'),
                          ),
                          DropdownMenuItem(
                            value: 'touch_grid',
                            child: Text('Large Touch Grid'),
                          ),
                        ],
                        onChanged: (v) => setState(() => posLayout = v!),
                      ),
                    ),
                    const SizedBox(width: 10),
                    field('cartWidth', 'Cart width', width: 130),
                  ],
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: gradient,
                onChanged: (v) => setState(() => gradient = v),
                title: const Text('Soft gradient background'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isDefault,
                onChanged: (v) => setState(() => isDefault = v),
                title: const Text('Default for this app'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: active,
                onChanged: (v) => setState(() => active = v),
                title: const Text('Active'),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Saving…' : 'Save template'),
        ),
      ],
    );
  }
}

class _BusinessBrandingPanel extends StatefulWidget {
  final PlatformConfigService service;
  final List<Business> businesses;
  final List<Map<String, dynamic>> templates;
  const _BusinessBrandingPanel({
    required this.service,
    required this.businesses,
    required this.templates,
  });
  @override
  State<_BusinessBrandingPanel> createState() => _BusinessBrandingPanelState();
}

class _BusinessBrandingPanelState extends State<_BusinessBrandingPanel> {
  String? tenantId;
  String appKey = 'client';
  String? templateId;
  bool loading = false;
  final primary = TextEditingController();
  final secondary = TextEditingController();
  final accent = TextEditingController();
  final background = TextEditingController();
  final surface = TextEditingController();
  final sidebar = TextEditingController();
  final border = TextEditingController();
  final radius = TextEditingController();
  String densityOverride = '';
  String posLayoutOverride = '';

  List<Map<String, dynamic>> get options => widget.templates
      .where(
        (t) => t['app_key']?.toString() == appKey && t['is_active'] != false,
      )
      .toList();

  Future<void> load() async {
    if (tenantId == null) return;
    setState(() => loading = true);
    try {
      final row = await widget.service.getTenantUiDesign(
        tenantId: tenantId!,
        appKey: appKey,
      );
      if (!mounted) return;
      final over = row['overrides'] is Map
          ? Map<String, dynamic>.from(row['overrides'] as Map)
          : <String, dynamic>{};
      setState(() {
        templateId = row['template_id']?.toString();
        primary.text = over['primary']?.toString() ?? '';
        secondary.text = over['secondary']?.toString() ?? '';
        accent.text = over['accent']?.toString() ?? '';
        background.text = over['background']?.toString() ?? '';
        surface.text = over['surface']?.toString() ?? '';
        sidebar.text = over['sidebar']?.toString() ?? '';
        border.text = over['border']?.toString() ?? '';
        radius.text = over['radius']?.toString() ?? '';
        densityOverride = over['density']?.toString() ?? '';
        posLayoutOverride = over['pos_layout']?.toString() ?? '';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (tenantId == null || templateId == null) return;
    Map<String, dynamic> o = {};
    void add(String k, TextEditingController c, {bool number = false}) {
      final v = c.text.trim();
      if (v.isNotEmpty) o[k] = number ? (double.tryParse(v) ?? 18) : v;
    }

    add('primary', primary);
    add('secondary', secondary);
    add('accent', accent);
    add('background', background);
    add('surface', surface);
    add('sidebar', sidebar);
    add('border', border);
    add('radius', radius, number: true);
    if (densityOverride.isNotEmpty) o['density'] = densityOverride;
    if (appKey == 'pos' && posLayoutOverride.isNotEmpty) {
      o['pos_layout'] = posLayoutOverride;
    }
    setState(() => loading = true);
    try {
      await widget.service.setTenantUiDesign(
        tenantId: tenantId!,
        appKey: appKey,
        templateId: templateId!,
        overrides: o,
      );
      if (mounted) {
        ThqNotify.info(
          context,
          'Business design saved',
          message: 'Re-login or restart an open app to refresh the design.',
          duration: const Duration(seconds: 5),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      primary,
      secondary,
      accent,
      background,
      surface,
      sidebar,
      border,
      radius,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(6),
      children: [
        const Text(
          'Business branding',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Choose a preset for each business, then override only the colors or shape values you want.',
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: tenantId,
                decoration: const InputDecoration(labelText: 'Business'),
                items: widget.businesses
                    .map(
                      (b) => DropdownMenuItem(value: b.id, child: Text(b.name)),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() => tenantId = v);
                  load();
                },
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                initialValue: appKey,
                decoration: const InputDecoration(labelText: 'App design'),
                items: const [
                  DropdownMenuItem(value: 'client', child: Text('Client ERP')),
                  DropdownMenuItem(value: 'pos', child: Text('POS')),
                ],
                onChanged: (v) {
                  setState(() {
                    appKey = v!;
                    templateId = null;
                  });
                  load();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          key: ValueKey('$appKey:$templateId'),
          initialValue: options.any((e) => e['id']?.toString() == templateId)
              ? templateId
              : null,
          decoration: const InputDecoration(labelText: 'Design template'),
          items: options
              .map(
                (t) => DropdownMenuItem(
                  value: t['id']?.toString(),
                  child: Text(t['name']?.toString() ?? ''),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => templateId = v),
        ),
        const SizedBox(height: 5),
        const Text(
          'Optional business overrides',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final e in [
              ('Primary', primary),
              ('Secondary', secondary),
              ('Accent', accent),
              ('Background', background),
              ('Surface', surface),
              ('Sidebar', sidebar),
              ('Border', border),
              ('Radius', radius),
            ])
              SizedBox(
                width: 210,
                child: TextField(
                  controller: e.$2,
                  decoration: InputDecoration(
                    labelText: e.$1,
                    hintText: 'Use template default',
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: densityOverride,
                decoration: const InputDecoration(
                  labelText: 'Density override',
                ),
                items: const [
                  DropdownMenuItem(
                    value: '',
                    child: Text('Use template default'),
                  ),
                  DropdownMenuItem(
                    value: 'comfortable',
                    child: Text('Comfortable'),
                  ),
                  DropdownMenuItem(value: 'compact', child: Text('Compact')),
                ],
                onChanged: (v) => setState(() => densityOverride = v ?? ''),
              ),
            ),
            if (appKey == 'pos') ...[
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: posLayoutOverride,
                  decoration: const InputDecoration(
                    labelText: 'POS layout override',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: '',
                      child: Text('Use template default'),
                    ),
                    DropdownMenuItem(
                      value: 'retail_grid',
                      child: Text('Retail Grid'),
                    ),
                    DropdownMenuItem(
                      value: 'compact_grid',
                      child: Text('Compact Grid'),
                    ),
                    DropdownMenuItem(
                      value: 'touch_grid',
                      child: Text('Large Touch Grid'),
                    ),
                  ],
                  onChanged: (v) => setState(() => posLayoutOverride = v ?? ''),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: loading || tenantId == null || templateId == null
                ? null
                : save,
            icon: const Icon(Icons.palette_outlined),
            label: Text(loading ? 'Saving…' : 'Apply business design'),
          ),
        ),
      ],
    );
  }
}
