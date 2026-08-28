import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/location_scope_service.dart';
import '../services/location_service.dart';

class LocationsScreen extends StatefulWidget {
  final ClientSession session;
  const LocationsScreen({super.key, required this.session});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  final LocationService _service = LocationService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _locations = const [];
  List<Map<String, dynamic>> _devices = const [];

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('locations.manage') ||
      widget.session.hasPermission('locations.manage_all');

  List<String> get _availablePosModules {
    const supported = {
      'sales',
      'inventory',
      'customers',
      'suppliers',
      'purchases',
      'expenses',
      'restaurant',
      'cashier_shifts',
      'terminal_day',
      'notifications',
      'tasks',
      'support',
      'logs',
    };
    return widget.session.modules
        .map((module) => module.key)
        .where(supported.contains)
        .toSet()
        .toList()
      ..sort();
  }

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
      final results = await Future.wait([
        _service.directory(widget.session.business.id),
        _service.list(widget.session.business.id),
        _service.stockOverview(widget.session.business.id),
      ]);
      final data = results[0] as Map<String, dynamic>;
      final tree = results[1] as List<Map<String, dynamic>>;
      final stock = results[2] as List<Map<String, dynamic>>;
      final treeById = {for (final row in tree) row['id']?.toString(): row};
      final stockById = {
        for (final row in stock) row['location_id']?.toString(): row,
      };
      if (!mounted) return;
      setState(() {
        _locations = (data['locations'] as List? ?? const [])
            .whereType<Map>()
            .map((row) {
              final merged = Map<String, dynamic>.from(row);
              final id = merged['id']?.toString();
              if (id != null) {
                merged.addAll(treeById[id] ?? const <String, dynamic>{});
                merged.addAll(stockById[id] ?? const <String, dynamic>{});
                merged['location_code'] ??= merged['code'];
                merged['location_type'] ??= merged['type'];
              }
              return merged;
            })
            .toList();
        _devices = (data['devices'] as List? ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _editLocation([Map<String, dynamic>? existing]) async {
    if (!_canManage) return;
    final code = TextEditingController(
      text: existing?['location_code']?.toString() ?? '',
    );
    final name = TextEditingController(
      text: existing?['name']?.toString() ?? '',
    );
    final phone = TextEditingController(
      text: existing?['phone']?.toString() ?? '',
    );
    final email = TextEditingController(
      text: existing?['email']?.toString() ?? '',
    );
    final gstin = TextEditingController(
      text: existing?['gstin']?.toString() ?? '',
    );
    final prefix = TextEditingController(
      text:
          existing?['invoice_prefix']?.toString() ??
          existing?['location_code']?.toString() ??
          '',
    );
    final settings = Map<String, dynamic>.from(
      existing?['settings'] as Map? ?? const {},
    );
    final addressLine1 = TextEditingController(
      text: existing?['address_line1']?.toString() ?? '',
    );
    final addressLine2 = TextEditingController(
      text: existing?['address_line2']?.toString() ?? '',
    );
    final city = TextEditingController(
      text: existing?['city']?.toString() ?? '',
    );
    final state = TextEditingController(
      text: existing?['state']?.toString() ?? '',
    );
    final postalCode = TextEditingController(
      text: existing?['postal_code']?.toString() ?? '',
    );
    final country = TextEditingController(
      text: existing?['country']?.toString() ?? 'India',
    );
    final logoUrl = TextEditingController(
      text: settings['logo_url']?.toString() ?? '',
    );
    var type = existing?['location_type']?.toString() ?? 'branch';
    var hierarchyRole =
        existing?['hierarchy_role']?.toString() ??
        (existing == null
            ? 'child_store'
            : (existing['location_code']?.toString().toUpperCase() == 'MAIN'
                  ? 'main_store'
                  : type == 'warehouse'
                  ? 'warehouse'
                  : 'child_store'));
    var sortOrder = (existing?['sort_order'] as num?)?.toInt() ?? 100;
    var active = existing?['active'] != false;
    final isExistingMain = existing != null && hierarchyRole == 'main_store';
    String? parentId = existing?['parent_location_id']?.toString();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          final parents = _locations.where(
            (location) =>
                location['id']?.toString() != existing?['id']?.toString(),
          );
          return AlertDialog(
            title: Text(existing == null ? 'Add child store' : 'Edit store'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: code,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Store code *',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: name,
                            decoration: const InputDecoration(
                              labelText: 'Store name *',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: hierarchyRole,
                            decoration: const InputDecoration(
                              labelText: 'Hierarchy role',
                            ),
                            items: [
                              if (isExistingMain)
                                const DropdownMenuItem(
                                  value: 'main_store',
                                  child: Text('MAIN STORE'),
                                ),
                              const DropdownMenuItem(
                                value: 'child_store',
                                child: Text('CHILD STORE'),
                              ),
                              const DropdownMenuItem(
                                value: 'warehouse',
                                child: Text('WAREHOUSE'),
                              ),
                              const DropdownMenuItem(
                                value: 'operational',
                                child: Text('OPERATIONAL LOCATION'),
                              ),
                            ],
                            onChanged: isExistingMain
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setLocalState(() {
                                      hierarchyRole = value;
                                      if (value == 'main_store') {
                                        parentId = null;
                                        type = 'head_office';
                                        sortOrder = 0;
                                      } else if (value == 'warehouse') {
                                        type = 'warehouse';
                                      }
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            initialValue: sortOrder.toString(),
                            enabled: !isExistingMain,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Sort order',
                            ),
                            onChanged: (value) =>
                                sortOrder = int.tryParse(value) ?? 100,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: type,
                            decoration: const InputDecoration(
                              labelText: 'Type',
                            ),
                            items:
                                const [
                                      'head_office',
                                      'branch',
                                      'store',
                                      'warehouse',
                                      'production',
                                      'office',
                                      'scrap',
                                      'restaurant',
                                      'kitchen',
                                      'service_base',
                                    ]
                                    .map(
                                      (value) => DropdownMenuItem(
                                        value: value,
                                        child: Text(
                                          value
                                              .replaceAll('_', ' ')
                                              .toUpperCase(),
                                        ),
                                      ),
                                    )
                                    .toList(),
                            onChanged: isExistingMain
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setLocalState(() => type = value);
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: parentId,
                            decoration: const InputDecoration(
                              labelText: 'Parent store',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Main / no parent'),
                              ),
                              ...parents.map(
                                (location) => DropdownMenuItem<String?>(
                                  value: location['id']?.toString(),
                                  child: Text(
                                    '${location['location_code']} • ${location['name']}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: hierarchyRole == 'main_store'
                                ? null
                                : (value) =>
                                      setLocalState(() => parentId = value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: email,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: gstin,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'GSTIN',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: prefix,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Store invoice prefix',
                              helperText: 'Example: MAIN / CAL / KOC',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressLine1,
                      decoration: const InputDecoration(
                        labelText: 'Address line 1',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressLine2,
                      decoration: const InputDecoration(
                        labelText: 'Address line 2',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: city,
                            decoration: const InputDecoration(
                              labelText: 'City',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: state,
                            decoration: const InputDecoration(
                              labelText: 'State',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: postalCode,
                            decoration: const InputDecoration(
                              labelText: 'Postal code',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: country,
                            decoration: const InputDecoration(
                              labelText: 'Country',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: logoUrl,
                            decoration: const InputDecoration(
                              labelText: 'Branch logo URL (optional)',
                              helperText:
                                  'Used on invoices when the selected template shows a logo.',
                            ),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: active,
                      title: const Text('Active store'),
                      onChanged: isExistingMain
                          ? null
                          : (value) => setLocalState(() => active = value),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (code.text.trim().isEmpty || name.text.trim().isEmpty) {
                    _message('Store code and name are required.');
                    return;
                  }
                  try {
                    await _service.saveLocation(
                      tenantId: widget.session.business.id,
                      id: existing?['id']?.toString(),
                      parentId: parentId,
                      code: code.text.trim().toUpperCase(),
                      name: name.text.trim(),
                      type: type,
                      phone: phone.text.trim(),
                      email: email.text.trim(),
                      gstin: gstin.text.trim().toUpperCase(),
                      addressLine1: addressLine1.text.trim(),
                      addressLine2: addressLine2.text.trim(),
                      city: city.text.trim(),
                      state: state.text.trim(),
                      postalCode: postalCode.text.trim(),
                      country: country.text.trim().isEmpty
                          ? 'India'
                          : country.text.trim(),
                      invoicePrefix: prefix.text.trim().toUpperCase(),
                      logoUrl: logoUrl.text.trim(),
                      hierarchyRole: hierarchyRole,
                      sortOrder: sortOrder,
                      active: active,
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    await _load();
                  } catch (error) {
                    _message(error.toString());
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    for (final controller in [
      code,
      name,
      phone,
      email,
      gstin,
      prefix,
      addressLine1,
      addressLine2,
      city,
      state,
      postalCode,
      country,
      logoUrl,
    ]) {
      controller.dispose();
    }
  }

  Future<void> _issueDevice() async {
    if (!_canManage) return;
    final active = _locations
        .where((location) => location['active'] != false)
        .toList();
    if (active.isEmpty) {
      _message('Create an active store first.');
      return;
    }

    var locationId = active.first['id'].toString();
    var appType = 'pos';
    var systemRole = 'pos';
    var platform = 'windows';
    final name = TextEditingController(text: 'Counter 1');
    final prefix = TextEditingController(text: 'POS1');
    final modules = <String>{'sales'};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          return AlertDialog(
            title: const Text('Add Client / POS system'),
            content: SizedBox(
              width: 690,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: locationId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Store'),
                      items: active
                          .map(
                            (location) => DropdownMenuItem(
                              value: location['id'].toString(),
                              child: Text(
                                '${location['location_code']} • ${location['name']}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setLocalState(() => locationId = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: appType,
                            decoration: const InputDecoration(labelText: 'App'),
                            items: const [
                              DropdownMenuItem(
                                value: 'pos',
                                child: Text('THQ POS'),
                              ),
                              DropdownMenuItem(
                                value: 'client',
                                child: Text('THQ Business'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setLocalState(() {
                                  appType = value;
                                  systemRole = appType == 'pos' ? 'pos' : 'office';
                                  if (appType == 'client') modules.clear();
                                  if (appType == 'pos' && modules.isEmpty) {
                                    modules.add('sales');
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: platform,
                            decoration: const InputDecoration(
                              labelText: 'Platform',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'windows',
                                child: Text('Windows'),
                              ),
                              DropdownMenuItem(
                                value: 'android',
                                child: Text('Android'),
                              ),
                              DropdownMenuItem(
                                value: 'web',
                                child: Text('Web / Browser'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setLocalState(() => platform = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    if (appType == 'client') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: systemRole,
                        decoration: const InputDecoration(labelText: 'System role'),
                        items: const [
                          DropdownMenuItem(value: 'back_office', child: Text('Back Office PC')),
                          DropdownMenuItem(value: 'office', child: Text('Office PC')),
                          DropdownMenuItem(value: 'inventory', child: Text('Inventory PC')),
                        ],
                        onChanged: (value) {
                          if (value != null) setLocalState(() => systemRole = value);
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: name,
                            decoration: const InputDecoration(
                              labelText: 'System name',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: prefix,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Terminal invoice prefix',
                              helperText: 'POS1 → POS1-INV-000001',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (appType == 'pos') ...[
                      const SizedBox(height: 18),
                      const Text(
                        'POS modules',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Only checked features will appear on this POS terminal.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _availablePosModules.map((module) {
                          final selected = modules.contains(module);
                          return FilterChip(
                            selected: selected,
                            label: Text(_nice(module)),
                            onSelected: (value) {
                              setLocalState(() {
                                if (value) {
                                  modules.add(module);
                                } else {
                                  modules.remove(module);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  if (appType == 'pos' && modules.isEmpty) {
                    _message('Select at least one POS module.');
                    return;
                  }
                  try {
                    final result = await _service.issueDevice(
                      tenantId: widget.session.business.id,
                      locationId: locationId,
                      name: name.text.trim().isEmpty
                          ? 'System'
                          : name.text.trim(),
                      appType: appType,
                      platform: platform,
                      modules: modules.toList(),
                      invoicePrefix: prefix.text.trim(),
                      systemRole: systemRole,
                    );
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                    if (!mounted) return;
                    await showDialog<void>(
                      context: this.context,
                      barrierDismissible: false,
                      builder: (context) => AlertDialog(
                        icon: const Icon(Icons.key_outlined, size: 38),
                        title: const Text('One-time activation code'),
                        content: SelectableText(
                          'Device: ${result['device_code']}\n'
                          'Activation Code: ${result['activation_code']}\n'
                          'Expires: ${result['expires_at']}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        actions: [
                          FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('I saved it'),
                          ),
                        ],
                      ),
                    );
                    await _load();
                  } catch (error) {
                    _message(error.toString());
                  }
                },
                icon: const Icon(Icons.key_outlined),
                label: const Text('Issue activation'),
              ),
            ],
          );
        },
      ),
    );

    name.dispose();
    prefix.dispose();
  }

  Future<void> _editDevice(Map<String, dynamic> device) async {
    if (!_canManage) return;
    final name = TextEditingController(text: device['name']?.toString() ?? '');
    final prefix = TextEditingController(
      text: device['invoice_prefix']?.toString() ?? '',
    );
    final modules = (device['allowed_modules'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();
    final isPos = device['app_type']?.toString() == 'pos';
    var locationId = device['location_id']?.toString() ?? (_locations.isNotEmpty ? _locations.first['id'].toString() : '');
    var systemRole = device['system_role']?.toString() ?? (isPos ? 'pos' : 'office');
    final activeLocations = _locations.where((row) => row['active'] != false || row['id']?.toString() == locationId).toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('Edit ${device['device_code']}'),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: locationId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Store / location'),
                  items: activeLocations.map((location) => DropdownMenuItem<String>(
                    value: location['id'].toString(),
                    child: Text('${location['location_code']} • ${location['name']}'),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) setLocalState(() => locationId = value);
                  },
                ),
                if (!isPos) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: systemRole,
                    decoration: const InputDecoration(labelText: 'System role'),
                    items: const [
                      DropdownMenuItem(value: 'back_office', child: Text('Back Office PC')),
                      DropdownMenuItem(value: 'office', child: Text('Office PC')),
                      DropdownMenuItem(value: 'inventory', child: Text('Inventory PC')),
                    ],
                    onChanged: (value) {
                      if (value != null) setLocalState(() => systemRole = value);
                    },
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: name,
                        decoration: const InputDecoration(
                          labelText: 'System name',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: prefix,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Invoice prefix',
                        ),
                      ),
                    ),
                  ],
                ),
                if (isPos) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Allowed POS modules',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availablePosModules.map((module) {
                      return FilterChip(
                        selected: modules.contains(module),
                        label: Text(_nice(module)),
                        onSelected: (value) {
                          setLocalState(() {
                            if (value) {
                              modules.add(module);
                            } else {
                              modules.remove(module);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await _service.updateDevice(
                    tenantId: widget.session.business.id,
                    deviceId: device['id'].toString(),
                    locationId: locationId,
                    name: name.text.trim(),
                    modules: modules.toList(),
                    invoicePrefix: prefix.text.trim(),
                    systemRole: systemRole,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _load();
                } catch (error) {
                  _message(error.toString());
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    prefix.dispose();
  }

  Future<void> _revoke(Map<String, dynamic> device) async {
    if (!_canManage) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke system?'),
        content: Text(
          '${device['device_code']} will no longer be able to sign in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.revokeDevice(
        tenantId: widget.session.business.id,
        deviceId: device['id'].toString(),
      );
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  String _nice(String value) => value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Stores & POS Systems',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Main store, child stores, Client installations and POS terminals.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              if (_canManage) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _editLocation(),
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Add Store'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _issueDevice,
                  icon: const Icon(Icons.computer_outlined),
                  label: const Text('Add System / POS'),
                ),
              ],
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _scopeCard(),
          const SizedBox(height: 20),
          const Text(
            'Stores',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (_locations.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No stores available.'),
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _locations.map(_locationCard).toList(),
            ),
          const SizedBox(height: 26),
          const Text(
            'Registered Systems',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (_devices.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No Client/POS systems registered.'),
              ),
            )
          else
            ..._devices.map(_deviceCard),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _scopeCard() {
    return ValueListenableBuilder<String?>(
      valueListenable: LocationScopeService.selectedLocationId,
      builder: (context, selected, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: const Icon(Icons.filter_alt_outlined),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Active reporting scope',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Sales, purchases, expenses, accounting and reports follow this selection.',
                    ),
                  ],
                ),
              ),
              Text(
                selected == null
                    ? 'ALL STORES'
                    : _locations
                              .where(
                                (location) =>
                                    location['id']?.toString() == selected,
                              )
                              .map(
                                (location) =>
                                    location['location_code']?.toString() ?? '',
                              )
                              .firstOrNull ??
                          'STORE',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _locationCard(Map<String, dynamic> location) {
    final devices = _devices
        .where(
          (device) =>
              device['location_id']?.toString() == location['id']?.toString(),
        )
        .length;
    final active = location['active'] != false;
    return Container(
      width: 310,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                child: Icon(
                  location['parent_location_id'] == null
                      ? Icons.storefront_outlined
                      : Icons.store_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location['name']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${location['location_code'] ?? ''} • ${location['tracking_code'] ?? ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_canManage)
                IconButton(
                  tooltip: 'Edit store',
                  onPressed: () => _editLocation(location),
                  icon: const Icon(Icons.edit_outlined),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Chip(
                label: Text(
                  _nice(
                    location['hierarchy_role']?.toString() ?? 'child_store',
                  ),
                ),
              ),
              Chip(
                label: Text(
                  _nice(location['location_type']?.toString() ?? 'store'),
                ),
              ),
              Chip(label: Text('$devices systems')),
              Chip(label: Text(active ? 'Active' : 'Inactive')),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Stock ${location['on_hand'] ?? 0}  •  Available ${location['available'] ?? 0}  •  In transit in ${location['in_transit_in'] ?? 0}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if ((location['gstin']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'GSTIN ${location['gstin']}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deviceCard(Map<String, dynamic> device) {
    final modules = (device['allowed_modules'] as List? ?? const [])
        .map((value) => value.toString())
        .toList();
    final location = _locations
        .where(
          (row) => row['id']?.toString() == device['location_id']?.toString(),
        )
        .map((row) => '${row['location_code']} • ${row['name']}')
        .firstOrNull;
    final active = device['status']?.toString() == 'active';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: active
                  ? Colors.green.shade50
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(
                device['app_type'] == 'pos'
                    ? Icons.point_of_sale_outlined
                    : Icons.computer_outlined,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${device['name'] ?? 'System'} • ${device['device_code'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(
                          (device['status'] ?? '').toString().toUpperCase(),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${location ?? 'Store'} • ${(device['app_type'] ?? '').toString().toUpperCase()} • ${device['tracking_code'] ?? ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if ((device['invoice_prefix']?.toString() ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Invoice prefix: ${device['invoice_prefix']}',
                      ),
                    ),
                  if (device['app_type'] == 'pos' && modules.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: modules
                          .map((module) => Chip(label: Text(_nice(module))))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            if (_canManage) ...[
              IconButton(
                tooltip: 'Edit system/modules',
                onPressed: () => _editDevice(device),
                icon: const Icon(Icons.tune_outlined),
              ),
              if (device['status'] != 'revoked')
                IconButton(
                  tooltip: 'Revoke',
                  onPressed: () => _revoke(device),
                  icon: const Icon(Icons.block_outlined),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
