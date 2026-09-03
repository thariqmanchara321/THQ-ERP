import 'package:flutter/material.dart';
import '../widgets/admin_home_button.dart';

import '../services/location_device_service.dart';

class BusinessLocationsDevicesScreen extends StatefulWidget {
  final String tenantId;
  final String businessName;

  const BusinessLocationsDevicesScreen({
    super.key,
    required this.tenantId,
    required this.businessName,
  });

  @override
  State<BusinessLocationsDevicesScreen> createState() =>
      _BusinessLocationsDevicesScreenState();
}

class _BusinessLocationsDevicesScreenState
    extends State<BusinessLocationsDevicesScreen> {
  final LocationDeviceService _service = LocationDeviceService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _identity = {};
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _devices = [];

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
      final result = await Future.wait([
        _service.identity(widget.tenantId),
        _service.locations(widget.tenantId),
        _service.systemsV46(widget.tenantId),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _identity = result[0] as Map<String, dynamic>;
        _locations = result[1] as List<Map<String, dynamic>>;
        _devices = result[2] as List<Map<String, dynamic>>;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  String? _mainLocationId() {
    for (final location in _locations) {
      if (location['hierarchy_role']?.toString() == 'main_store' ||
          location['location_code']?.toString().toUpperCase() == 'MAIN') {
        return location['id']?.toString();
      }
    }
    return null;
  }

  Future<void> _editLocation([Map<String, dynamic>? existing]) async {
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
    final invoicePrefix = TextEditingController(
      text:
          existing?['invoice_prefix']?.toString() ??
          existing?['location_code']?.toString() ??
          '',
    );
    final address1 = TextEditingController(
      text: existing?['address_line1']?.toString() ?? '',
    );
    final address2 = TextEditingController(
      text: existing?['address_line2']?.toString() ?? '',
    );
    final city = TextEditingController(
      text: existing?['city']?.toString() ?? '',
    );
    final state = TextEditingController(
      text: existing?['state']?.toString() ?? 'Kerala',
    );
    final postal = TextEditingController(
      text: existing?['postal_code']?.toString() ?? '',
    );
    final country = TextEditingController(
      text: existing?['country']?.toString() ?? 'India',
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
    String? parentLocationId = existing?['parent_location_id']?.toString();
    if (existing == null && hierarchyRole != 'main_store') {
      for (final location in _locations) {
        if (location['hierarchy_role']?.toString() == 'main_store' ||
            location['location_code']?.toString().toUpperCase() == 'MAIN') {
          parentLocationId = location['id']?.toString();
          break;
        }
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            final possibleParents = _locations.where(
              (location) =>
                  location['id']?.toString() != existing?['id']?.toString(),
            );
            return AlertDialog(
              title: Text(
                existing == null
                    ? 'Add Store / Location'
                    : 'Edit Store / Location',
              ),
              content: SizedBox(
                width: 760,
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
                                labelText: 'Location code *',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: name,
                              decoration: const InputDecoration(
                                labelText: 'Location name *',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
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
                                          parentLocationId = null;
                                          type = 'head_office';
                                          sortOrder = 0;
                                        } else if (value == 'warehouse') {
                                          type = 'warehouse';
                                          parentLocationId ??=
                                              _mainLocationId();
                                        } else {
                                          parentLocationId ??=
                                              _mainLocationId();
                                        }
                                      });
                                    },
                            ),
                          ),
                          const SizedBox(width: 10),
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
                      const SizedBox(height: 10),
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
                                        setLocalState(() {
                                          type = value;
                                          if (value == 'warehouse') {
                                            hierarchyRole = 'warehouse';
                                          } else if (const [
                                            'production',
                                            'office',
                                            'scrap',
                                          ].contains(value)) {
                                            hierarchyRole = 'operational';
                                          } else if (!isExistingMain &&
                                              const [
                                                'store',
                                                'branch',
                                              ].contains(value)) {
                                            hierarchyRole = 'child_store';
                                          }
                                        });
                                      }
                                    },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              initialValue: parentLocationId,
                              decoration: const InputDecoration(
                                labelText: 'Parent location',
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('No parent / root'),
                                ),
                                ...possibleParents.map(
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
                                  : (value) {
                                      setLocalState(
                                        () => parentLocationId = value,
                                      );
                                    },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
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
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: email,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: gstin,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'GSTIN',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: invoicePrefix,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Invoice prefix',
                          helperText: 'Example MAIN → MAIN-INV-000001',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: address1,
                        decoration: const InputDecoration(
                          labelText: 'Address line 1',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: address2,
                        decoration: const InputDecoration(
                          labelText: 'Address line 2',
                        ),
                      ),
                      const SizedBox(height: 10),
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
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: state,
                              decoration: const InputDecoration(
                                labelText: 'State',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: postal,
                              decoration: const InputDecoration(
                                labelText: 'PIN / Postal code',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: country,
                              decoration: const InputDecoration(
                                labelText: 'Country',
                              ),
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: active,
                        title: const Text('Active location'),
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
                      _message('Location code and name are required.');
                      return;
                    }
                    try {
                      await _service.saveLocation(
                        tenantId: widget.tenantId,
                        id: existing?['id']?.toString(),
                        parentLocationId: parentLocationId,
                        code: code.text,
                        name: name.text,
                        type: type,
                        phone: phone.text,
                        email: email.text,
                        gstin: gstin.text,
                        addressLine1: address1.text,
                        addressLine2: address2.text,
                        city: city.text,
                        state: state.text,
                        postal: postal.text,
                        country: country.text,
                        invoicePrefix: invoicePrefix.text.trim().isEmpty
                            ? code.text
                            : invoicePrefix.text,
                        hierarchyRole: hierarchyRole,
                        sortOrder: sortOrder,
                        active: active,
                      );
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      await _load();
                    } catch (error) {
                      _message(error.toString());
                    }
                  },
                  child: Text(
                    existing == null ? 'Create Location' : 'Save Changes',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    for (final controller in [
      code,
      name,
      phone,
      email,
      gstin,
      invoicePrefix,
      address1,
      address2,
      city,
      state,
      postal,
      country,
    ]) {
      controller.dispose();
    }
  }

  static const _posModules = <String>[
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
  ];

  String _niceModule(String value) {
    if (value == 'cashier_shifts') return 'Cashier Shift';
    if (value == 'terminal_day') return 'Terminal Daily';
    return value
        .split('_')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  Future<void> _createSystem() async {
    final activeLocations = _locations
        .where((location) => location['active'] != false)
        .toList();
    if (activeLocations.isEmpty) {
      _message('Create an active location first.');
      return;
    }

    var locationId = activeLocations.first['id'].toString();
    var appType = 'pos';
    var systemRole = 'pos';
    var platformHint = 'windows';
    final name = TextEditingController(text: 'Counter 1');
    String suggestedPrefix;
    try {
      suggestedPrefix = await _service.nextPosInvoicePrefix(widget.tenantId);
    } catch (_) {
      suggestedPrefix = 'Automatic';
    }
    if (!mounted) return;
    final invoicePrefix = TextEditingController(text: suggestedPrefix);
    final selectedModules = <String>{'sales'};

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocalState) => AlertDialog(
          title: const Text('Add System'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: locationId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Location / child store',
                    ),
                    items: activeLocations
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: appType,
                          decoration: const InputDecoration(
                            labelText: 'Application',
                          ),
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
                                systemRole = appType == 'pos'
                                    ? 'pos'
                                    : 'office';
                                if (appType == 'client') {
                                  selectedModules.clear();
                                }
                                if (appType == 'pos' &&
                                    selectedModules.isEmpty) {
                                  selectedModules.add('sales');
                                }
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: platformHint,
                          decoration: const InputDecoration(
                            labelText: 'Expected platform',
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
                              setLocalState(() => platformHint = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (appType == 'client') ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: systemRole,
                      decoration: const InputDecoration(
                        labelText: 'System role',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'back_office',
                          child: Text('Back Office PC'),
                        ),
                        DropdownMenuItem(
                          value: 'office',
                          child: Text('Office PC'),
                        ),
                        DropdownMenuItem(
                          value: 'inventory',
                          child: Text('Inventory PC'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null)
                          setLocalState(() => systemRole = value);
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: name,
                          decoration: const InputDecoration(
                            labelText: 'System / counter name',
                          ),
                        ),
                      ),
                      if (appType == 'pos') ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: invoicePrefix,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Terminal invoice prefix',
                              helperText:
                                  'Assigned automatically and never reused. Example: POS05 → POS05-INV-000001',
                              suffixIcon: Icon(Icons.auto_awesome_outlined),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (appType == 'pos') ...[
                    const SizedBox(height: 18),
                    const Text(
                      'POS modules',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose exactly what this terminal should show. Cashier Shift and Terminal Daily are independent and can be enabled or disabled separately.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _posModules.map((module) {
                        return FilterChip(
                          selected: selectedModules.contains(module),
                          label: Text(_niceModule(module)),
                          onSelected: (selected) {
                            setLocalState(() {
                              if (selected) {
                                selectedModules.add(module);
                              } else {
                                selectedModules.remove(module);
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
                if (appType == 'pos' && selectedModules.isEmpty) {
                  _message('Select at least one POS module.');
                  return;
                }
                try {
                  final created = await _service.createSystem(
                    tenantId: widget.tenantId,
                    locationId: locationId,
                    name: name.text.trim().isEmpty
                        ? 'System'
                        : name.text.trim(),
                    appType: appType,
                    systemRole: systemRole,
                    platformHint: platformHint,
                    moduleKeys: selectedModules.toList(),
                    // Empty means the server atomically allocates the next permanent POS prefix.
                    invoicePrefix: '',
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  final assignedPrefix = created['invoice_prefix']?.toString();
                  _message(
                    appType == 'pos'
                        ? 'POS created with invoice prefix ${assignedPrefix ?? 'automatic'}. Activate the system to issue its one-time code.'
                        : 'System created. Activate the system to issue its one-time code.',
                  );
                  await _load();
                } catch (error) {
                  _message(error.toString());
                }
              },
              icon: const Icon(Icons.add_to_queue),
              label: const Text('Create System'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    invoicePrefix.dispose();
  }

  Future<void> _activateSystem() async {
    final pending = _devices
        .where((d) => d['status'] == 'pending' || d['status'] == 'inactive')
        .toList();
    if (pending.isEmpty) {
      _message('There are no pending or inactive systems to activate.');
      return;
    }
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Activate System'),
        content: SizedBox(
          width: 720,
          height: 430,
          child: ListView.separated(
            itemCount: pending.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final d = pending[index];
              return ListTile(
                leading: Icon(
                  d['app_type'] == 'pos' ? Icons.point_of_sale : Icons.computer,
                ),
                title: Text('${d['device_code']} • ${d['name']}'),
                subtitle: Text(
                  '${d['location_code']} • ${d['location_name']} • ${d['app_type']} • Prefix ${d['invoice_prefix'] ?? '-'}',
                ),
                trailing: FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, d),
                  child: const Text('Select'),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    try {
      final result = await _service.activateSystem(
        tenantId: widget.tenantId,
        deviceId: selected['id'].toString(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (codeContext) => AlertDialog(
          icon: const Icon(Icons.key_outlined, size: 38),
          title: const Text('One-Time Activation Details'),
          content: SelectableText(
            'Business Code: ${result['business_code'] ?? _identity['business_code']}\n'
            'System: ${result['device_code']}\n'
            'One-Time Password: ${result['activation_code']}\n'
            'Expires: ${result['expires_at']}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(codeContext),
              child: const Text('I saved it'),
            ),
          ],
        ),
      );
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _editDevice(Map<String, dynamic> device) async {
    final isPos = device['app_type']?.toString() == 'pos';
    final activeLocations = _locations
        .where((location) => location['active'] != false)
        .toList();
    var locationId =
        device['location_id']?.toString() ??
        (activeLocations.isEmpty ? '' : activeLocations.first['id'].toString());
    var systemRole =
        device['system_role']?.toString() ?? (isPos ? 'pos' : 'office');
    final name = TextEditingController(text: device['name']?.toString() ?? '');
    final invoicePrefix = TextEditingController(
      text: device['invoice_prefix']?.toString() ?? '',
    );
    final selectedModules = (device['allowed_modules'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocalState) => AlertDialog(
          title: Text('Configure ${device['device_code']}'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: locationId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Assigned store / location',
                      helperText:
                          'A system can be moved later without changing its system identity.',
                    ),
                    items: activeLocations
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
                      if (value != null)
                        setLocalState(() => locationId = value);
                    },
                  ),
                  if (!isPos) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: systemRole,
                      decoration: const InputDecoration(
                        labelText: 'System role',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'back_office',
                          child: Text('Back Office PC'),
                        ),
                        DropdownMenuItem(
                          value: 'office',
                          child: Text('Office PC'),
                        ),
                        DropdownMenuItem(
                          value: 'inventory',
                          child: Text('Inventory PC'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null)
                          setLocalState(() => systemRole = value);
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
                      if (isPos) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: invoicePrefix,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Terminal invoice prefix',
                              helperText:
                                  'Editable until this POS has transaction history. Then it is locked by the server.',
                              suffixIcon: Icon(Icons.edit_outlined),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (isPos) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'Allowed POS modules',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cashier Shifts and Terminal Daily are operational modules and can be enabled per POS.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _posModules
                          .map(
                            (module) => FilterChip(
                              selected: selectedModules.contains(module),
                              label: Text(_niceModule(module)),
                              onSelected: (selected) {
                                setLocalState(() {
                                  if (selected) {
                                    selectedModules.add(module);
                                  } else {
                                    selectedModules.remove(module);
                                  }
                                });
                              },
                            ),
                          )
                          .toList(),
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
            FilledButton(
              onPressed: () async {
                if (locationId.isEmpty) {
                  _message('Choose an active store/location.');
                  return;
                }
                if (isPos && selectedModules.isEmpty) {
                  _message('Select at least one POS module.');
                  return;
                }
                try {
                  await _service.updateDevice(
                    tenantId: widget.tenantId,
                    deviceId: device['id'].toString(),
                    locationId: locationId,
                    name: name.text.trim(),
                    moduleKeys: selectedModules.toList(),
                    invoicePrefix: invoicePrefix.text.trim(),
                    systemRole: isPos ? 'pos' : systemRole,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  _message('System settings saved.');
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
    invoicePrefix.dispose();
  }

  Future<void> _deleteSystem(Map<String, dynamic> device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        title: const Text('Delete / archive system?'),
        content: Text(
          '${device['device_code']} • ${device['name']}\n\n'
          'Unused systems are deleted. Systems with transactions, shifts, or installation history are safely archived so old invoices and audit history remain valid.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await _service.deleteSystem(
        tenantId: widget.tenantId,
        systemId: device['id'].toString(),
        reason: 'Removed from THQ Admin',
      );
      _message(result['message']?.toString() ?? 'System removed.');
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _deleteLocation(Map<String, dynamic> location) async {
    if (location['hierarchy_role']?.toString() == 'main_store' ||
        location['location_code']?.toString().toUpperCase() == 'MAIN') {
      _message('MAIN STORE cannot be deleted.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        title: const Text('Delete / archive store?'),
        content: Text(
          '${location['location_code']} • ${location['name']}\n\n'
          'Move or remove all assigned systems first. A store with transaction/accounting/stock history will be archived instead of destroying historical records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await _service.deleteLocation(
        tenantId: widget.tenantId,
        locationId: location['id'].toString(),
        reason: 'Removed from THQ Admin',
      );
      _message(result['message']?.toString() ?? 'Store removed.');
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  void _showActivationDetails(Map<String, dynamic> device) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Activation Details'),
        content: SelectableText(
          'Business Code: ${_identity['business_code'] ?? '-'}\n'
          'System: ${device['device_code'] ?? '-'}\n'
          'Name: ${device['name'] ?? '-'}\n'
          'Type: ${device['app_type'] ?? '-'}\n'
          'Store: ${device['location_name'] ?? '-'}\n'
          'Prefix: ${device['invoice_prefix'] ?? '-'}\n'
          'Status: ${device['status'] ?? '-'}\n'
          'Installation: ${device['installation_id'] ?? 'Not bound'}\n'
          'Activated: ${device['activated_at'] ?? 'Not activated'}\n'
          'Last seen: ${device['last_seen_at'] ?? 'Never'}\n'
          'Deactivated: ${device['deactivated_at'] ?? '-'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _address(Map<String, dynamic> location) {
    return [
          location['address_line1'],
          location['city'],
          location['state'],
          location['postal_code'],
        ]
        .where((value) => value != null && value.toString().trim().isNotEmpty)
        .join(', ');
  }

  String _systemRoleLabel(Map<String, dynamic> device) {
    final role =
        device['system_role']?.toString() ??
        (device['app_type'] == 'pos' ? 'pos' : 'office');
    return switch (role) {
      'pos' => 'POS',
      'back_office' => 'Back Office PC',
      'inventory' => 'Inventory PC',
      _ => 'Office PC',
    };
  }

  Widget _systemTile(Map<String, dynamic> device) {
    final status = device['status']?.toString() ?? '';
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      leading: Icon(
        device['app_type'] == 'pos' ? Icons.point_of_sale : Icons.computer,
      ),
      title: Text('${device['device_code']} • ${device['name']}'),
      subtitle: Text(
        '${_systemRoleLabel(device)} • ${device['platform_hint'] ?? 'any platform'}'
        '${device['app_type'] == 'pos' ? ' • Prefix ${device['invoice_prefix'] ?? '-'}' : ''}\n'
        'Last seen ${device['last_seen_at'] ?? 'never'}',
      ),
      isThreeLine: true,
      trailing: Wrap(
        spacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Chip(label: Text(status.toUpperCase())),
          IconButton(
            tooltip: 'Configure / move system',
            onPressed: () => _editDevice(device),
            icon: const Icon(Icons.tune_outlined),
          ),
          IconButton(
            tooltip: 'Activation details',
            onPressed: () => _showActivationDetails(device),
            icon: const Icon(Icons.info_outline),
          ),
          if (status == 'active')
            IconButton(
              tooltip: 'Deactivate system',
              onPressed: () async {
                try {
                  await _service.deactivateSystem(
                    widget.tenantId,
                    device['id'].toString(),
                    reason: 'Deactivated from Admin',
                  );
                  await _load();
                } catch (error) {
                  _message(error.toString());
                }
              },
              icon: const Icon(Icons.power_settings_new, color: Colors.orange),
            ),
          IconButton(
            tooltip: 'Delete / archive system',
            onPressed: () => _deleteSystem(device),
            icon: const Icon(Icons.delete_outline, color: Colors.red),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeSystems = _devices
        .where((d) => d['status']?.toString() != 'revoked')
        .length;
    final archivedSystems = _devices
        .where((d) => d['status']?.toString() == 'revoked')
        .length;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: Text(
          '${widget.businessName} | Locations & Systems',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        actions: const [AdminHomeButton()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 25,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Business Structure',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                '${_locations.length} location(s) | '
                                '$activeSystems active/configured system(s)'
                                '${archivedSystems > 0 ? ' | $archivedSystems archived' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 7.6,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh',
                          visualDensity: VisualDensity.compact,
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded, size: 17),
                        ),
                        const SizedBox(width: 3),
                        OutlinedButton.icon(
                          onPressed: () => _editLocation(),
                          icon: const Icon(Icons.add_business, size: 14),
                          label: const Text('Store'),
                        ),
                        const SizedBox(width: 4),
                        OutlinedButton.icon(
                          onPressed: _createSystem,
                          icon: const Icon(Icons.add_to_queue, size: 14),
                          label: const Text('System / POS'),
                        ),
                        const SizedBox(width: 4),
                        FilledButton.icon(
                          onPressed: _activateSystem,
                          icon: const Icon(Icons.key_outlined, size: 14),
                          label: const Text('Activate'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.key_outlined,
                          size: 15,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Business Code',
                          style: TextStyle(
                            fontSize: 7.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            _identity['business_code']?.toString() ?? '-',
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .5,
                            ),
                          ),
                        ),
                        Text(
                          'Use with one-time system activation code',
                          style: TextStyle(
                            fontSize: 7.3,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 5),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 8,
                          color: scheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 5),
                  Expanded(
                    child: _locations.isEmpty
                        ? const Center(child: Text('No locations configured.'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemCount: _locations.length,
                              itemBuilder: (context, index) {
                                final location = _locations[index];
                                final systems = _devices
                                    .where(
                                      (device) =>
                                          device['location_id']?.toString() ==
                                              location['id']?.toString() &&
                                          device['status']?.toString() !=
                                              'revoked',
                                    )
                                    .toList();
                                final isMain =
                                    location['hierarchy_role']?.toString() ==
                                        'main_store' ||
                                    location['location_code']
                                            ?.toString()
                                            .toUpperCase() ==
                                        'MAIN';

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 5),
                                  decoration: BoxDecoration(
                                    color: scheme.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    children: [
                                      Container(
                                        constraints: const BoxConstraints(
                                          minHeight: 48,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        color: scheme.surfaceContainerHighest
                                            .withValues(alpha: .32),
                                        child: Row(
                                          children: [
                                            Icon(
                                              location['location_type']
                                                          ?.toString() ==
                                                      'warehouse'
                                                  ? Icons.warehouse_outlined
                                                  : Icons
                                                        .store_mall_directory_outlined,
                                              size: 16,
                                              color: scheme.primary,
                                            ),
                                            const SizedBox(width: 7),
                                            Expanded(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${location['location_code']} | '
                                                    '${location['name']}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 8.8,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${isMain ? 'MAIN STORE' : (location['location_type'] ?? 'store')} | '
                                                    '${_address(location)}'
                                                    '${location['gstin'] == null ? '' : ' | GSTIN ${location['gstin']}'}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 7.2,
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Text(
                                              '${systems.length} system(s)',
                                              style: TextStyle(
                                                fontSize: 7.4,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              location['active'] == false
                                                  ? 'INACTIVE'
                                                  : 'ACTIVE',
                                              style: TextStyle(
                                                fontSize: 7,
                                                fontWeight: FontWeight.w900,
                                                color:
                                                    location['active'] == false
                                                    ? scheme.onSurfaceVariant
                                                    : scheme.primary,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Edit store',
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: () =>
                                                  _editLocation(location),
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 14,
                                              ),
                                            ),
                                            if (!isMain)
                                              IconButton(
                                                tooltip:
                                                    'Delete / archive store',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                onPressed: () =>
                                                    _deleteLocation(location),
                                                icon: Icon(
                                                  Icons.delete_outline,
                                                  size: 14,
                                                  color: scheme.error,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (systems.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'No systems assigned to this location.',
                                              style: TextStyle(
                                                fontSize: 7.6,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        )
                                      else
                                        ...systems.map(_systemTile),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
