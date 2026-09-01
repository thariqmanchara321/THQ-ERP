import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/inventory_service.dart';

class ProductUnitsScreen extends StatefulWidget {
  final ClientSession session;
  final String variantId;
  final String productName;

  const ProductUnitsScreen({
    super.key,
    required this.session,
    required this.variantId,
    required this.productName,
  });

  @override
  State<ProductUnitsScreen> createState() => _ProductUnitsScreenState();
}

class _ProductUnitsScreenState extends State<ProductUnitsScreen> {
  final InventoryService _service = InventoryService();
  final _formKey = GlobalKey<FormState>();
  List<InventoryUnit> _units = const [];
  final List<_UnitDraft> _rows = [];
  String _baseCode = 'PCS';
  String _baseStep = '1';
  bool _baseCuttingAllowed = false;
  String _baseCuttingCharge = '0';
  bool _loading = true;
  bool _saving = false;
  String? _error;

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
        _service.getUnits(tenantId: widget.session.business.id),
        _service.getProductUnits(
          tenantId: widget.session.business.id,
          variantId: widget.variantId,
        ),
      ]);
      final units = results[0] as List<InventoryUnit>;
      final configured = results[1] as List<ProductUnitOption>;
      final base = configured.where((u) => u.isBase).firstOrNull;
      if (!mounted) return;
      setState(() {
        _units = units;
        _baseCode = base?.code ?? (units.any((u) => u.code == 'PCS') ? 'PCS' : units.first.code);
        _baseStep = base?.quantityStep.toString() ?? '1';
        _baseCuttingAllowed = base?.cuttingAllowed ?? false;
        _baseCuttingCharge = base?.cuttingCharge.toString() ?? '0';
        _rows
          ..clear()
          ..addAll(configured.where((u) => !u.isBase).map(_UnitDraft.fromOption));
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InventoryUnit? _unitById(String id) {
    for (final unit in _units) {
      if (unit.id == id) return unit;
    }
    return null;
  }

  void _addUnit() {
    final used = _rows.map((r) => r.unitId).toSet();
    final available = _units.where((u) => u.code != _baseCode && !used.contains(u.id)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No more units available.')));
      return;
    }
    setState(() => _rows.add(_UnitDraft(unitId: available.first.id)));
  }

  Future<void> _createCustomUnit() async {
    final draft = await showDialog<_NewUnitDraft>(
      context: context,
      builder: (_) => const _CreateUnitDialog(),
    );
    if (draft == null || !mounted) return;
    try {
      await _service.saveUnit(
        tenantId: widget.session.business.id,
        code: draft.code,
        name: draft.name,
        group: draft.group,
        decimalPlaces: draft.decimalPlaces,
        allowFractional: draft.allowFractional,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unit ${draft.code.toUpperCase()} created.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ids = _rows.where((r) => r.active).map((r) => r.unitId).toList();
    if (ids.toSet().length != ids.length) {
      setState(() => _error = 'The same unit cannot be configured twice.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.saveProductUnits(
        tenantId: widget.session.business.id,
        variantId: widget.variantId,
        baseUnitCode: _baseCode,
        units: <Map<String, dynamic>>[
          {
            'unit_id': _units.where((u) => u.code == _baseCode).first.id,
            'quantity_step': double.tryParse(_baseStep) ?? 1,
            'cutting_allowed': _baseCuttingAllowed,
            'cutting_charge': double.tryParse(_baseCuttingCharge) ?? 0,
          },
          ..._rows.map((r) => r.toMap()),
        ],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Units and conversions saved.')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Units • ${widget.productName}'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _units.isEmpty
              ? Center(child: Text(_error!))
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Text('Base inventory unit', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('All stock balances are stored in this base unit. Purchase/sale units convert into it.'),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _units.any((u) => u.code == _baseCode) ? _baseCode : null,
                        decoration: const InputDecoration(labelText: 'Base Unit', border: OutlineInputBorder()),
                        items: _units.map((u) => DropdownMenuItem(value: u.code, child: Text('${u.name} (${u.code})'))).toList(),
                        onChanged: _saving ? null : (value) {
                          if (value == null) return;
                          setState(() {
                            _baseCode = value;
                            final baseUnit = _units.firstWhere((u) => u.code == value);
                            _baseStep = baseUnit.allowFractional
                                ? '0.1'
                                : '1';
                            _baseCuttingAllowed = false;
                            _baseCuttingCharge = '0';
                            _rows.removeWhere((r) => _unitById(r.unitId)?.code == value);
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 180,
                            child: TextFormField(
                              key: ValueKey('base-step-$_baseCode-$_baseStep'),
                              initialValue: _baseStep,
                              decoration: const InputDecoration(labelText: 'Base quantity step', border: OutlineInputBorder()),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (v) => _baseStep = v,
                              validator: _positive,
                            ),
                          ),
                          FilterChip(
                            label: const Text('Cut / Partial Quantity'),
                            selected: _baseCuttingAllowed,
                            onSelected: _saving ? null : (v) => setState(() => _baseCuttingAllowed = v),
                          ),
                          if (_baseCuttingAllowed)
                            SizedBox(
                              width: 200,
                              child: TextFormField(
                                key: ValueKey('base-cut-$_baseCuttingCharge'),
                                initialValue: _baseCuttingCharge,
                                decoration: const InputDecoration(labelText: 'Cutting charge', prefixText: '₹ ', border: OutlineInputBorder()),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (v) => _baseCuttingCharge = v,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(child: Text('Additional purchase / sale units', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
                          OutlinedButton.icon(onPressed: _saving ? null : _createCustomUnit, icon: const Icon(Icons.straighten_outlined), label: const Text('New Custom Unit')),
                          const SizedBox(width: 8),
                          FilledButton.icon(onPressed: _saving ? null : _addUnit, icon: const Icon(Icons.add), label: const Text('Add Unit')),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text('Example: base METER, add COIL with conversion 90. Selling 2 COIL deducts 180 METER.'),
                      const SizedBox(height: 16),
                      if (_rows.isEmpty)
                        const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No alternate units configured. The product uses only its base unit.'))),
                      ..._rows.asMap().entries.map((entry) => _unitCard(entry.key, entry.value)),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Saving...' : 'Save Unit Configuration'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _unitCard(int index, _UnitDraft row) {
    final candidates = _units.where((u) => u.code != _baseCode).toList();
    final unit = _unitById(row.unitId);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('unit-${row.unitId}-$index'),
                  initialValue: candidates.any((u) => u.id == row.unitId) ? row.unitId : null,
                  decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder()),
                  items: candidates.map((u) => DropdownMenuItem(value: u.id, child: Text('${u.name} (${u.code})'))).toList(),
                  onChanged: _saving ? null : (value) => setState(() => row.unitId = value ?? row.unitId),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: _saving ? null : () => setState(() => _rows.removeAt(index)), icon: const Icon(Icons.delete_outline), tooltip: 'Remove'),
            ]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(width: 190, child: TextFormField(initialValue: row.factor, decoration: InputDecoration(labelText: '1 ${unit?.code ?? 'Unit'} = base qty', border: const OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) => row.factor = v, validator: _positive)),
                SizedBox(width: 150, child: TextFormField(initialValue: row.step, decoration: const InputDecoration(labelText: 'Qty step', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) => row.step = v, validator: _positive)),
                SizedBox(width: 180, child: TextFormField(initialValue: row.salePrice, decoration: const InputDecoration(labelText: 'Sale price / unit', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) => row.salePrice = v)),
                SizedBox(width: 180, child: TextFormField(initialValue: row.purchaseCost, decoration: const InputDecoration(labelText: 'Purchase cost / unit', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) => row.purchaseCost = v)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(label: const Text('Sale'), selected: row.allowSale, onSelected: _saving ? null : (v) => setState(() => row.allowSale = v)),
                FilterChip(label: const Text('Purchase'), selected: row.allowPurchase, onSelected: _saving ? null : (v) => setState(() => row.allowPurchase = v)),
                FilterChip(label: const Text('Default Sale'), selected: row.defaultSale, onSelected: _saving ? null : (v) => setState(() {
                  for (final x in _rows) {
                    x.defaultSale = false;
                  }
                  row.defaultSale = v;
                  if (v) row.allowSale = true;
                })),
                FilterChip(label: const Text('Default Purchase'), selected: row.defaultPurchase, onSelected: _saving ? null : (v) => setState(() {
                  for (final x in _rows) {
                    x.defaultPurchase = false;
                  }
                  row.defaultPurchase = v;
                  if (v) row.allowPurchase = true;
                })),
                FilterChip(label: const Text('Cut / Partial'), selected: row.cuttingAllowed, onSelected: _saving ? null : (v) => setState(() => row.cuttingAllowed = v)),
              ],
            ),
            if (row.cuttingAllowed) ...[
              const SizedBox(height: 12),
              SizedBox(width: 220, child: TextFormField(initialValue: row.cuttingCharge, decoration: const InputDecoration(labelText: 'Optional cutting charge', prefixText: '₹ ', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) => row.cuttingCharge = v)),
            ],
          ],
        ),
      ),
    );
  }

  String? _positive(String? value) {
    final number = double.tryParse(value?.trim() ?? '');
    return number == null || number <= 0 ? 'Enter a number > 0' : null;
  }
}

class _UnitDraft {
  String unitId;
  String factor;
  String step;
  String salePrice;
  String purchaseCost;
  String cuttingCharge;
  bool allowSale;
  bool allowPurchase;
  bool defaultSale;
  bool defaultPurchase;
  bool cuttingAllowed;
  bool active;

  _UnitDraft({
    required this.unitId,
    this.factor = '1',
    this.step = '1',
    this.salePrice = '',
    this.purchaseCost = '',
    this.cuttingCharge = '0',
    this.allowSale = true,
    this.allowPurchase = true,
    this.defaultSale = false,
    this.defaultPurchase = false,
    this.cuttingAllowed = false,
    this.active = true,
  });

  factory _UnitDraft.fromOption(ProductUnitOption value) => _UnitDraft(
        unitId: value.unitId,
        factor: value.conversionToBase.toString(),
        step: value.quantityStep.toString(),
        salePrice: value.salePrice?.toString() ?? '',
        purchaseCost: value.purchaseCost?.toString() ?? '',
        cuttingCharge: value.cuttingCharge.toString(),
        allowSale: value.allowSale,
        allowPurchase: value.allowPurchase,
        defaultSale: value.isDefaultSale,
        defaultPurchase: value.isDefaultPurchase,
        cuttingAllowed: value.cuttingAllowed,
        active: value.active,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'unit_id': unitId,
        'conversion_to_base': double.tryParse(factor) ?? 1,
        'quantity_step': double.tryParse(step) ?? 1,
        'sale_price': double.tryParse(salePrice),
        'purchase_cost': double.tryParse(purchaseCost),
        'cutting_allowed': cuttingAllowed,
        'cutting_charge': double.tryParse(cuttingCharge) ?? 0,
        'allow_sale': allowSale,
        'allow_purchase': allowPurchase,
        'is_default_sale': defaultSale,
        'is_default_purchase': defaultPurchase,
        'active': active,
      };
}

class _NewUnitDraft {
  final String code;
  final String name;
  final String group;
  final int decimalPlaces;
  final bool allowFractional;

  const _NewUnitDraft({
    required this.code,
    required this.name,
    required this.group,
    required this.decimalPlaces,
    required this.allowFractional,
  });
}

class _CreateUnitDialog extends StatefulWidget {
  const _CreateUnitDialog();

  @override
  State<_CreateUnitDialog> createState() => _CreateUnitDialogState();
}

class _CreateUnitDialogState extends State<_CreateUnitDialog> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  String _group = 'custom';
  int _decimals = 0;
  bool _fractional = false;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Custom Unit'),
      content: Form(
        key: _form,
        child: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Code', hintText: 'BAG'),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Code is required' : null,
              ),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name', hintText: 'Bag'),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _group,
                decoration: const InputDecoration(labelText: 'Unit group'),
                items: const [
                  DropdownMenuItem(value: 'custom', child: Text('Custom')),
                  DropdownMenuItem(value: 'count', child: Text('Count')),
                  DropdownMenuItem(value: 'pack', child: Text('Pack')),
                  DropdownMenuItem(value: 'length', child: Text('Length')),
                  DropdownMenuItem(value: 'weight', child: Text('Weight')),
                  DropdownMenuItem(value: 'volume', child: Text('Volume')),
                  DropdownMenuItem(value: 'time', child: Text('Time')),
                ],
                onChanged: (v) => setState(() => _group = v ?? 'custom'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow fractional quantities'),
                value: _fractional,
                onChanged: (v) => setState(() {
                  _fractional = v;
                  if (!v) _decimals = 0;
                  if (v && _decimals == 0) _decimals = 3;
                }),
              ),
              if (_fractional)
                DropdownButtonFormField<int>(
                  initialValue: _decimals.clamp(1, 6).toInt(),
                  decoration: const InputDecoration(labelText: 'Decimal places'),
                  items: [for (var i = 1; i <= 6; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                  onChanged: (v) => setState(() => _decimals = v ?? 3),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              _NewUnitDraft(
                code: _code.text.trim().toUpperCase(),
                name: _name.text.trim(),
                group: _group,
                decimalPlaces: _fractional ? _decimals : 0,
                allowFractional: _fractional,
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
