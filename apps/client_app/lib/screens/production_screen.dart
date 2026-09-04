import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../models/inventory_product.dart';
import '../services/inventory_service.dart';
import '../services/location_scope_service.dart';
import '../services/production_service.dart';
import '../widgets/searchable_select.dart';
import 'purchases_screen.dart';

class ProductionScreen extends StatefulWidget {
  final ClientSession session;
  const ProductionScreen({super.key, required this.session});
  @override
  State<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends State<ProductionScreen> {
  final _service = ProductionService();
  final _inventory = InventoryService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _recipes = [];
  List<Map<String, dynamic>> _runs = [];
  List<InventoryProduct> _products = [];
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
      final rows = await Future.wait([
        _service.recipes(widget.session.business.id),
        _service.runs(
          widget.session.business.id,
          locationId: LocationScopeService.currentForRead(widget.session),
        ),
        _inventory.getProducts(tenantId: widget.session.business.id),
      ]);
      if (!mounted) return;
      setState(() {
        _recipes = rows[0] as List<Map<String, dynamic>>;
        _runs = rows[1] as List<Map<String, dynamic>>;
        _products = (rows[2] as List<InventoryProduct>)
            .where(
              (p) =>
                  p.variantStatus == 'active' &&
                  p.productStatus == 'active' &&
                  p.itemType == 'stock',
            )
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _name(String id) {
    for (final p in _products) {
      if (p.variantId == id) return '${p.productName} • ${p.sku}';
    }
    return id;
  }

  Future<void> _recipeDialog() async {
    if (!widget.session.hasPermission('production.manage')) {
      _snack('You do not have production.manage permission.');
      return;
    }
    if (_products.isEmpty) {
      _snack('Create inventory products first.');
      return;
    }
    final name = TextEditingController(),
        qty = TextEditingController(text: '1'),
        notes = TextEditingController();
    String output = _products.first.variantId;
    final inputs = <Map<String, dynamic>>[];
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New Production Recipe / BOM'),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Recipe name'),
                  ),
                  const SizedBox(height: 10),
                  SearchableSelect<String>(
                    value: output,
                    labelText: 'Finished product',
                    isRequired: true,
                    hintText: 'Search product, SKU, barcode or part number',
                    prefixIcon: Icons.inventory_2_outlined,
                    options: _products
                        .map(
                          (p) => SearchableSelectOption<String>(
                            value: p.variantId,
                            label: p.productName,
                            subtitle: [p.sku, p.barcode, p.partNumber]
                                .where(
                                  (v) =>
                                      v != null &&
                                      v.toString().trim().isNotEmpty,
                                )
                                .join(' • '),
                            searchText:
                                '${p.productName} ${p.sku} ${p.barcode ?? ''} ${p.partNumber ?? ''} ${p.searchCodes}',
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => output = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: qty,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Finished quantity per batch',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Raw materials',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          setLocal(
                            () => inputs.add({
                              'input_variant_id': _products.first.variantId,
                              'quantity': 1.0,
                              'waste_percent': 0.0,
                            }),
                          );
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  ...inputs.asMap().entries.map((entry) {
                    final i = entry.key, row = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: SearchableSelect<String>(
                              value: row['input_variant_id'].toString(),
                              labelText: 'Raw material',
                              isRequired: true,
                              hintText:
                                  'Search product, SKU, barcode or part number',
                              prefixIcon: Icons.inventory_2_outlined,
                              options: _products
                                  .map(
                                    (p) => SearchableSelectOption<String>(
                                      value: p.variantId,
                                      label: p.productName,
                                      subtitle: [p.sku, p.barcode, p.partNumber]
                                          .where(
                                            (v) =>
                                                v != null &&
                                                v.toString().trim().isNotEmpty,
                                          )
                                          .join(' • '),
                                      searchText:
                                          '${p.productName} ${p.sku} ${p.barcode ?? ''} ${p.partNumber ?? ''} ${p.searchCodes}',
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setLocal(() => row['input_variant_id'] = v);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: '${row['quantity']}',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Qty',
                              ),
                              onChanged: (v) =>
                                  row['quantity'] = double.tryParse(v) ?? 0,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setLocal(() => inputs.removeAt(i)),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await _service.saveRecipe(
                    tenantId: widget.session.business.id,
                    name: name.text,
                    outputVariantId: output,
                    outputQuantity: double.tryParse(qty.text) ?? 0,
                    items: inputs,
                    notes: notes.text,
                  );
                  if (context.mounted) Navigator.pop(context);
                  await _load();
                } catch (e) {
                  _snack(e.toString());
                }
              },
              child: const Text('Save Recipe'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    qty.dispose();
    notes.dispose();
  }

  Future<void> _runDialog() async {
    if (!widget.session.hasPermission('production.run') &&
        !widget.session.hasPermission('production.manage')) {
      _snack('Production run permission required.');
      return;
    }
    if (_recipes.isEmpty) {
      _snack('Create a production recipe first.');
      return;
    }
    String recipe = _recipes.first['id'].toString();
    final batches = TextEditingController(text: '1'),
        notes = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Run Production'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: recipe,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Recipe'),
                  items: _recipes
                      .where((r) => r['active'] != false)
                      .map(
                        (r) => DropdownMenuItem(
                          value: r['id'].toString(),
                          child: Text(r['name']?.toString() ?? 'Recipe'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setLocal(() => recipe = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: batches,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Number of batches',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 10),
                Text(
                  'Production origin: selected store. Stock posting uses the current inventory engine/location.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                try {
                  final r = await _service.execute(
                    tenantId: widget.session.business.id,
                    recipeId: recipe,
                    locationId: LocationScopeService.currentForCreate(
                      widget.session,
                    ),
                    batches: double.tryParse(batches.text) ?? 0,
                    notes: notes.text,
                  );
                  if (context.mounted) Navigator.pop(context);
                  _snack('${r['run_number']} completed. Stock updated.');
                  await _load();
                } catch (e) {
                  _snack(e.toString());
                }
              },
              icon: const Icon(Icons.factory_outlined),
              label: const Text('Post Production'),
            ),
          ],
        ),
      ),
    );
    batches.dispose();
    notes.dispose();
  }

  void _snack(String text) {
    if (mounted) {
      ThqNotify.showSnackBar(context, SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Production',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text('Raw materials → recipes/BOM → finished stock'),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PurchasesScreen(session: widget.session),
                  ),
                ),
                icon: const Icon(Icons.shopping_cart_outlined),
                label: const Text('Raw Material Purchase'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _recipeDialog,
                icon: const Icon(Icons.schema_outlined),
                label: const Text('New Recipe'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _runDialog,
                icon: const Icon(Icons.factory_outlined),
                label: const Text('Run Production'),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _stat('Recipes', _recipes.length.toString(), Icons.schema),
              _stat('Runs', _runs.length.toString(), Icons.factory),
              _stat(
                'Location',
                widget.session.device?.locationName ?? '-',
                Icons.store,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Recipes / BOM',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._recipes.map(
            (r) => Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.precision_manufacturing_outlined),
                ),
                title: Text(r['name']?.toString() ?? ''),
                subtitle: Text(
                  '${r['tracking_code'] ?? ''} • Output ${r['output_quantity']} × ${_name(r['output_variant_id'].toString())}\n${(r['items'] as List? ?? const []).length} raw material(s)',
                ),
                isThreeLine: true,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Production History',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._runs.map(
            (r) => Card(
              child: ListTile(
                leading: Icon(
                  r['status'] == 'completed'
                      ? Icons.check_circle_outline
                      : Icons.timelapse,
                ),
                title: Text(r['run_number']?.toString() ?? ''),
                subtitle: Text(
                  '${r['recipe_name'] ?? ''} • ${r['location_name'] ?? ''} • ${r['planned_batches']} batch(es)\n${r['tracking_code'] ?? ''}',
                ),
                isThreeLine: true,
                trailing: Chip(
                  label: Text((r['status'] ?? '').toString().toUpperCase()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) => Container(
    width: 230,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.grey.shade600)),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
