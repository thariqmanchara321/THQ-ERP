import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../services/aggregate_yard_service.dart';

class DriverMasterScreen extends StatefulWidget {
  final ClientSession session;

  const DriverMasterScreen({super.key, required this.session});

  @override
  State<DriverMasterScreen> createState() => _DriverMasterScreenState();
}

class _DriverMasterScreenState extends State<DriverMasterScreen> {
  final AggregateYardService _service = AggregateYardService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _drivers = const [];
  bool _loading = true;
  String? _error;
  bool _showInactive = false;
  bool _isTableView = true;

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('aggregate_yard.manage') ||
      widget.session.hasPermission('logistics_operations.manage');

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDrivers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await _service.drivers(
        tenantId: widget.session.business.id,
        query: _searchCtrl.text.trim(),
        limit: 200,
      );
      if (mounted) {
        setState(() {
          _drivers = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _openDriverDialog([Map<String, dynamic>? driver]) async {
    if (!_canManage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission aggregate_yard.manage required.')),
      );
      return;
    }

    final isEdit = driver != null;
    final nameCtrl = TextEditingController(text: driver?['name'] ?? '');
    final phoneCtrl = TextEditingController(text: driver?['phone'] ?? '');
    final codeCtrl = TextEditingController(text: driver?['driver_code'] ?? '');
    final licenseCtrl = TextEditingController(text: driver?['license_number'] ?? '');
    final expiryCtrl = TextEditingController(text: driver?['license_expiry'] ?? '');
    final addressCtrl = TextEditingController(text: driver?['address'] ?? '');
    final wageCtrl = TextEditingController(
      text: driver?['default_wage'] != null ? '${driver!['default_wage']}' : '0',
    );
    final notesCtrl = TextEditingController(text: driver?['notes'] ?? '');
    var active = driver?['active'] ?? true;
    var saving = false;

    final saved = await showThqDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(isEdit ? 'Edit Driver' : 'Add New Driver'),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: nameCtrl,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Driver name *',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: codeCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Driver code / ID',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: wageCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Default wage per trip (₹)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: licenseCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Licence number',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: expiryCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Licence expiry (YYYY-MM-DD)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: addressCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Active Driver', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Available for trips and load dispatch', style: TextStyle(fontSize: 11)),
                    value: active,
                    onChanged: (v) => setDlgState(() => active = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Driver name is required.')),
                        );
                        return;
                      }

                      setDlgState(() => saving = true);
                      try {
                        await _service.saveDriver(
                          tenantId: widget.session.business.id,
                          driver: {
                            if (isEdit) 'id': driver['id'] ?? driver['driver_id'],
                            'name': name,
                            'phone': phoneCtrl.text.trim(),
                            'driver_code': codeCtrl.text.trim(),
                            'license_number': licenseCtrl.text.trim(),
                            'license_expiry': expiryCtrl.text.trim(),
                            'address': addressCtrl.text.trim(),
                            'default_wage': double.tryParse(wageCtrl.text.trim()) ?? 0,
                            'notes': notesCtrl.text.trim(),
                            'active': active,
                          },
                        );
                        if (dialogCtx.mounted) {
                          Navigator.of(dialogCtx).pop(true);
                        }
                      } catch (err) {
                        if (dialogCtx.mounted) {
                          setDlgState(() => saving = false);
                          ScaffoldMessenger.of(dialogCtx).showSnackBar(
                            SnackBar(content: Text(err.toString())),
                          );
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save Driver'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      await _loadDrivers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = _drivers.where((d) => _showInactive || (d['active'] != false)).toList();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 46,
        title: const Text('Driver Master', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: _isTableView ? 'Switch to Cards View' : 'Switch to Data Table View',
            icon: Icon(_isTableView ? Icons.grid_view_rounded : Icons.table_rows_rounded),
            onPressed: () => setState(() => _isTableView = !_isTableView),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload drivers',
            onPressed: _loading ? null : _loadDrivers,
          ),
          if (_canManage)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => _openDriverDialog(),
                icon: const Icon(Icons.person_add_outlined, size: 16),
                label: const Text('Add Driver', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(fontSize: 12),
                      onChanged: (_) => _loadDrivers(),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        hintText: 'Search drivers by name, phone, code or licence…',
                        hintStyle: TextStyle(fontSize: 11.5),
                        prefixIcon: Icon(Icons.search, size: 16),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Show Inactive', style: TextStyle(fontSize: 11)),
                  selected: _showInactive,
                  onSelected: (val) => setState(() => _showInactive = val),
                ),
              ],
            ),
          ),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else if (_error != null)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!, style: TextStyle(fontSize: 11, color: scheme.onErrorContainer)),
            ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _loading ? 'Loading drivers…' : 'No drivers found.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  )
                : _isTableView
                    ? _buildDriversTable(filtered, scheme)
                    : _buildDriversList(filtered, scheme),
          ),
        ],
      ),
    );
  }

  Widget _buildDriversTable(List<Map<String, dynamic>> drivers, ColorScheme scheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(1.2), // Driver ID/Code
            1: FlexColumnWidth(2.0), // Name
            2: FlexColumnWidth(1.4), // Phone
            3: FlexColumnWidth(1.8), // License & Expiry
            4: FlexColumnWidth(1.2), // Default Wage
            5: FlexColumnWidth(1.0), // Status
            6: FlexColumnWidth(1.0), // Actions
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
              ),
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Text('Driver ID / Code', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text('Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text('Phone', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text('License & Expiry', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text('Default Wage (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text('Status', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('Actions', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            ...drivers.map((d) {
              final name = d['name'] ?? '';
              final phone = d['phone'] ?? '';
              final code = d['driver_code'] ?? '';
              final license = d['license_number'] ?? '';
              final expiry = d['license_expiry'] ?? '';
              final wage = d['default_wage'];
              final active = d['active'] != false;

              return TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                ),
                children: [
                  // Code
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      code.isNotEmpty ? code : '—',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  // Name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      name,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  // Phone
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      phone.isNotEmpty ? phone : '—',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  // License
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      license.isNotEmpty ? '$license ${expiry.isNotEmpty ? '($expiry)' : ''}' : '—',
                      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  // Wage
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      wage != null ? '₹$wage' : '—',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                  // Status
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFF00875A).withValues(alpha: 0.12)
                              : scheme.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          active ? 'ACTIVE' : 'INACTIVE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: active ? const Color(0xFF00875A) : scheme.error,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Actions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        tooltip: 'Edit Driver',
                        onPressed: _canManage ? () => _openDriverDialog(d) : null,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDriversList(List<Map<String, dynamic>> drivers, ColorScheme scheme) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: drivers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final d = drivers[index];
        final name = d['name'] ?? '';
        final phone = d['phone'] ?? '';
        final code = d['driver_code'] ?? '';
        final license = d['license_number'] ?? '';
        final expiry = d['license_expiry'] ?? '';
        final wage = d['default_wage'];
        final active = d['active'] != false;

        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'D',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                          if (code.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(code, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
                            ),
                          ],
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: active
                                  ? const Color(0xFF00875A).withValues(alpha: 0.12)
                                  : scheme.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              active ? 'ACTIVE' : 'INACTIVE',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                color: active ? const Color(0xFF00875A) : scheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 10,
                        children: [
                          if (phone.isNotEmpty) Text('📞 $phone', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                          if (license.isNotEmpty) Text('🪪 $license', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                          if (expiry.isNotEmpty) Text('Exp: $expiry', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                          if (wage != null && wage > 0) Text('💰 Wage: ₹$wage', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_canManage)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    tooltip: 'Edit Driver',
                    onPressed: () => _openDriverDialog(d),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
