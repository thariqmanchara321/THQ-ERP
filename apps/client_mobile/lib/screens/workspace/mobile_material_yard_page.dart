import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/mobile_session.dart';
import '../../services/mobile_client_service.dart';
import '../../widgets/mobile_workspace_widgets.dart';

class MobileMaterialYardPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileMaterialYardPage({
    super.key,
    required this.session,
    required this.service,
    this.locationId,
  });

  @override
  State<MobileMaterialYardPage> createState() => _MobileMaterialYardPageState();
}

class _MobileMaterialYardPageState extends State<MobileMaterialYardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();
  late Future<List<Map<String, dynamic>>> _loadsFuture;
  late Future<List<Map<String, dynamic>>> _ratesFuture;
  String _selectedStatus = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    _loadsFuture = widget.service.materialLoads(
      widget.session,
      locationId: widget.locationId,
      status: _selectedStatus == 'all' ? null : _selectedStatus,
    );
    _ratesFuture = widget.service.materialDailyRates(
      widget.session,
      locationId: widget.locationId,
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await Future.wait([_loadsFuture, _ratesFuture]);
  }

  void _createLoad() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _CreateMaterialLoadSheet(
        session: widget.session,
        service: widget.service,
        locationId: widget.locationId,
      ),
    );
    if (created == true && mounted) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Material Yard & Quarry'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.local_shipping_outlined), text: 'Load Register'),
            Tab(icon: Icon(Icons.price_change_outlined), text: 'Daily Rates Board'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createLoad,
        icon: const Icon(Icons.add_road_rounded),
        label: const Text('New Load'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLoadsTab(),
          _buildRatesTab(),
        ],
      ),
    );
  }

  Widget _buildLoadsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search vehicle, customer, driver or material...',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              _FilterChip(
                label: 'All',
                selected: _selectedStatus == 'all',
                onSelected: () => setState(() {
                  _selectedStatus = 'all';
                  _reload();
                }),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Draft',
                selected: _selectedStatus == 'draft',
                onSelected: () => setState(() {
                  _selectedStatus = 'draft';
                  _reload();
                }),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Confirmed',
                selected: _selectedStatus == 'confirmed',
                onSelected: () => setState(() {
                  _selectedStatus = 'confirmed';
                  _reload();
                }),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Invoiced',
                selected: _selectedStatus == 'invoiced',
                onSelected: () => setState(() {
                  _selectedStatus = 'invoiced';
                  _reload();
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _loadsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const WorkspaceLoadingList();
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 40, color: Theme.of(context).colorScheme.error),
                        const SizedBox(height: 10),
                        Text('Error loading material loads: ${snapshot.error}', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _refresh, child: const Text('Retry')),
                      ],
                    ),
                  ),
                );
              }

              final allRows = snapshot.data ?? [];
              final query = _searchCtrl.text.trim().toLowerCase();
              final filtered = allRows.where((row) {
                if (query.isEmpty) return true;
                final truck = (row['vehicle_registration'] ?? row['vehicle_id'] ?? '').toString().toLowerCase();
                final driver = (row['driver_name'] ?? '').toString().toLowerCase();
                final customer = (row['customer_name'] ?? row['party_name'] ?? '').toString().toLowerCase();
                final material = (row['product_name'] ?? '').toString().toLowerCase();
                final loadNum = (row['load_number'] ?? '').toString().toLowerCase();
                return truck.contains(query) ||
                    driver.contains(query) ||
                    customer.contains(query) ||
                    material.contains(query) ||
                    loadNum.contains(query);
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_shipping_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 10),
                      const Text('No material loads found', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        'Tap "New Load" to dispatch trucks from the quarry or yard.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = filtered[i];
                    final loadNumber = item['load_number'] ?? 'LD-${item['id']}';
                    final truck = item['vehicle_registration'] ?? 'No Truck Reg';
                    final driver = item['driver_name'] ?? '';
                    final material = item['product_name'] ?? 'Aggregate';
                    final qty = item['quantity'] ?? item['net_weight'] ?? 0;
                    final unit = item['unit_code'] ?? 'tons';
                    final customer = item['customer_name'] ?? 'Direct Yard Cash';
                    final status = (item['status'] ?? 'draft').toString().toLowerCase();
                    final invoiceNum = item['invoice_number'] ?? item['sale_number'];
                    final date = item['load_date']?.toString().split('T').first ?? '';

                    Color statusColor;
                    switch (status) {
                      case 'invoiced':
                        statusColor = Colors.green;
                        break;
                      case 'confirmed':
                        statusColor = Colors.blue;
                        break;
                      default:
                        statusColor = Colors.orange;
                    }

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.local_shipping_rounded, size: 18),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$truck',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$material • $qty $unit',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Customer: $customer${driver.isNotEmpty ? " • Driver: $driver" : ""}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const Divider(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  loadNumber,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.outline,
                                      ),
                                ),
                                if (invoiceNum != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Inv: $invoiceNum',
                                      style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.bold),
                                    ),
                                  )
                                else if (date.isNotEmpty)
                                  Text(
                                    date,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRatesTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _ratesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error loading rates: ${snapshot.error}'));
        }

        final rates = snapshot.data ?? [];
        if (rates.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.price_change_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 10),
                const Text('No daily rates configured yet', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Rates can be established per material/product for this yard.'),
              ],
            ),
          );
        }

        return _DailyRatesEditor(
          session: widget.session,
          service: widget.service,
          initialRates: rates,
          locationId: widget.locationId ?? widget.session.locationId,
          onSaved: _refresh,
        );
      },
    );
  }
}

class _DailyRatesEditor extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final List<Map<String, dynamic>> initialRates;
  final String locationId;
  final VoidCallback onSaved;

  const _DailyRatesEditor({
    required this.session,
    required this.service,
    required this.initialRates,
    required this.locationId,
    required this.onSaved,
  });

  @override
  State<_DailyRatesEditor> createState() => _DailyRatesEditorState();
}

class _DailyRatesEditorState extends State<_DailyRatesEditor> {
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final rate in widget.initialRates) {
      final key = (rate['variant_id'] ?? rate['product_id'] ?? rate['id']).toString();
      final val = rate['base_rate'] ?? rate['rate'] ?? rate['unit_price'] ?? 0;
      _controllers[key] = TextEditingController(text: val.toString());
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final ratesToSave = widget.initialRates.map((r) {
        final key = (r['variant_id'] ?? r['product_id'] ?? r['id']).toString();
        final textVal = _controllers[key]?.text.trim() ?? '0';
        final rateNum = double.tryParse(textVal) ?? 0.0;
        return {
          'variant_id': key,
          'product_id': r['product_id'] ?? key,
          'base_rate': rateNum,
          'min_rate': r['min_rate'] ?? rateNum,
        };
      }).toList();

      await widget.service.saveMaterialDailyRates(
        widget.session,
        locationId: widget.locationId,
        date: DateTime.now(),
        rates: ratesToSave,
      );

      if (!mounted) return;
      setState(() => _saving = false);
      ThqNotify.success(context, 'Rates Saved', message: 'Daily yard rates updated successfully.');
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ThqNotify.error(context, 'Save Failed', message: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.session.currency;

    return Scaffold(
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        itemCount: widget.initialRates.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final item = widget.initialRates[i];
          final key = (item['variant_id'] ?? item['product_id'] ?? item['id']).toString();
          final name = item['product_name'] ?? item['name'] ?? 'Material';
          final unit = item['unit_code'] ?? 'ton';
          final ctrl = _controllers[key];

          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(
                          'Per $unit',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: ctrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixText: '$currency ',
                        labelText: 'Rate',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      bottomSheet: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -3)),
            ],
          ),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Updating Rates...' : 'Save Daily Rates'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ),
    );
  }
}

class _CreateMaterialLoadSheet extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const _CreateMaterialLoadSheet({
    required this.session,
    required this.service,
    this.locationId,
  });

  @override
  State<_CreateMaterialLoadSheet> createState() =>
      _CreateMaterialLoadSheetState();
}

class _CreateMaterialLoadSheetState extends State<_CreateMaterialLoadSheet> {
  final _vehicleCtrl = TextEditingController();
  final _driverCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _materialCtrl = TextEditingController(text: '20mm Aggregate');
  final _qtyCtrl = TextEditingController(text: '10');
  final _rateCtrl = TextEditingController();
  final _customerCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _vehicleCtrl.dispose();
    _driverCtrl.dispose();
    _phoneCtrl.dispose();
    _materialCtrl.dispose();
    _qtyCtrl.dispose();
    _rateCtrl.dispose();
    _customerCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmLoad() async {
    if (_vehicleCtrl.text.trim().isEmpty) {
      ThqNotify.error(context, 'Validation', message: 'Vehicle registration is required.');
      return;
    }

    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (qty <= 0) {
      ThqNotify.error(context, 'Validation', message: 'Quantity must be positive.');
      return;
    }

    setState(() => _saving = true);
    try {
      final locId = widget.locationId ?? widget.session.locationId;
      await widget.service.materialYardAction(
        widget.session,
        action: 'create',
        locationId: locId,
        data: {
          'vehicle_registration': _vehicleCtrl.text.trim().toUpperCase(),
          'driver_name': _driverCtrl.text.trim(),
          'driver_phone': _phoneCtrl.text.trim(),
          'product_name': _materialCtrl.text.trim(),
          'quantity': qty,
          'rate': double.tryParse(_rateCtrl.text.trim()) ?? 0,
          'customer_name': _customerCtrl.text.trim(),
        },
      );

      if (!mounted) return;
      setState(() => _saving = false);
      ThqNotify.success(context, 'Load Recorded', message: 'Material load dispatched successfully.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ThqNotify.error(context, 'Dispatch Failed', message: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Row(
              children: [
                const Icon(Icons.add_road_rounded),
                const SizedBox(width: 8),
                const Text('Dispatch Material Load', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _vehicleCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Vehicle Registration Number *',
                hintText: 'e.g. KL-07-CD-5678',
                prefixIcon: const Icon(Icons.local_shipping_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _driverCtrl,
                    decoration: InputDecoration(
                      labelText: 'Driver Name',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Driver Phone',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _materialCtrl,
              decoration: InputDecoration(
                labelText: 'Material / Product *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Quantity (Tons / M3) *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Rate / Unit',
                      prefixText: '${widget.session.currency} ',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _customerCtrl,
              decoration: InputDecoration(
                labelText: 'Customer / Buyer Name',
                hintText: 'Direct cash or client account',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _confirmLoad,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Recording Dispatch...' : 'Confirm Load Dispatch'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
