import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/custom_fields_service.dart';

class CustomFieldsScreen extends StatefulWidget {
  final ClientSession session;
  const CustomFieldsScreen({super.key, required this.session});

  @override
  State<CustomFieldsScreen> createState() => _CustomFieldsScreenState();
}

class _CustomFieldsScreenState extends State<CustomFieldsScreen> {
  final _service = CustomFieldsService();
  static const _entities = <String, String>{
    'product': 'Product',
    'customer': 'Customer',
    'supplier': 'Supplier',
    'vehicle': 'Vehicle',
    'job_card': 'Workshop Job Card',
    'service_job': 'Service Job',
    'patient': 'Patient',
    'lab_order': 'Lab Order',
  };
  String _entity = 'product';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('settings.manage');

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
      _rows = await _service.list(
        tenantId: widget.session.business.id,
        entityType: _entity,
      );
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    if (!_canManage) return;
    final label = TextEditingController(text: row?['label']?.toString() ?? '');
    final key = TextEditingController(
      text: row?['field_key']?.toString() ?? '',
    );
    final options = TextEditingController(
      text: (row?['options'] as List? ?? const [])
          .map((e) => e.toString())
          .join(', '),
    );
    var type = row?['field_type']?.toString() ?? 'text';
    var requiredField = row?['required'] == true;
    var searchable = row?['searchable'] == true;
    var invoiceVisible = row?['invoice_visible'] == true;
    var active = row == null || row['active'] != false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(row == null ? 'Add Custom Field' : 'Edit Custom Field'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: label,
                    decoration: const InputDecoration(
                      labelText: 'Label *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: key,
                    decoration: const InputDecoration(
                      labelText: 'Field Key *',
                      hintText: 'oem_number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: 'Field Type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'text', child: Text('Text')),
                      DropdownMenuItem(value: 'number', child: Text('Number')),
                      DropdownMenuItem(value: 'date', child: Text('Date')),
                      DropdownMenuItem(
                        value: 'dropdown',
                        child: Text('Dropdown'),
                      ),
                      DropdownMenuItem(
                        value: 'checkbox',
                        child: Text('Checkbox'),
                      ),
                      DropdownMenuItem(
                        value: 'multi_select',
                        child: Text('Multi-select'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setLocal(() => type = value);
                    },
                  ),
                  if (type == 'dropdown' || type == 'multi_select') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: options,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Options',
                        hintText: 'Option A, Option B, Option C',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Required'),
                    value: requiredField,
                    onChanged: (v) => setLocal(() => requiredField = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Searchable'),
                    value: searchable,
                    onChanged: (v) => setLocal(() => searchable = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show on invoice when supported'),
                    value: invoiceVisible,
                    onChanged: (v) => setLocal(() => invoiceVisible = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: active,
                    onChanged: (v) => setLocal(() => active = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (label.text.trim().isEmpty || key.text.trim().isEmpty) {
                  return;
                }
                await _service.save(
                  tenantId: widget.session.business.id,
                  id: row?['id']?.toString(),
                  entityType: _entity,
                  fieldKey: key.text,
                  label: label.text,
                  fieldType: type,
                  requiredField: requiredField,
                  searchable: searchable,
                  invoiceVisible: invoiceVisible,
                  options: options.text
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList(),
                  active: active,
                  sortOrder:
                      (row?['sort_order'] as num?)?.toInt() ?? _rows.length,
                );
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    key.dispose();
    options.dispose();
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom Fields')),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    initialValue: _entity,
                    decoration: const InputDecoration(
                      labelText: 'Entity',
                      border: OutlineInputBorder(),
                    ),
                    items: _entities.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _entity = value);
                      _load();
                    },
                  ),
                ),
                if (_canManage)
                  FilledButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Field'),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                  ? const Center(
                      child: Text('No custom fields for this entity yet.'),
                    )
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        return Card(
                          child: ListTile(
                            title: Text(row['label']?.toString() ?? ''),
                            subtitle: Text(
                              '${row['field_key']} • ${row['field_type']} • '
                              '${row['active'] == true ? 'Active' : 'Inactive'}',
                            ),
                            trailing: _canManage
                                ? IconButton(
                                    onPressed: () => _edit(row),
                                    icon: const Icon(Icons.edit_outlined),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
