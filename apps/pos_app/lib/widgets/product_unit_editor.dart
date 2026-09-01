import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';

/// Mutable unit configuration used by product create/edit forms.
///
/// Stock always remains in [baseCode]. Alternate sale/purchase units carry a
/// conversion factor back to that base unit.
class ProductUnitEditorController {
  ProductUnitEditorController({
    required List<InventoryUnit> units,
    required String baseCode,
    List<ProductUnitOption> configured = const <ProductUnitOption>[],
  })  : units = List<InventoryUnit>.unmodifiable(units),
        baseCode = _validBase(units, baseCode) {
    final base = configured.where((value) => value.isBase).firstOrNull;
    if (base != null && units.any((unit) => unit.code == base.code)) {
      this.baseCode = base.code;
      baseStep = _format(base.quantityStep);
      baseCuttingAllowed = base.cuttingAllowed;
      baseCuttingCharge = _format(base.cuttingCharge);
    }
    rows.addAll(
      configured
          .where((value) => !value.isBase)
          .where((value) => units.any((unit) => unit.id == value.unitId))
          .map(ProductUnitDraft.fromOption),
    );
  }

  final List<InventoryUnit> units;
  String baseCode;
  String baseStep = '1';
  bool baseCuttingAllowed = false;
  String baseCuttingCharge = '0';
  final List<ProductUnitDraft> rows = <ProductUnitDraft>[];

  static String _validBase(List<InventoryUnit> units, String requested) {
    if (units.any((unit) => unit.code == requested)) return requested;
    if (units.any((unit) => unit.code == 'PCS')) return 'PCS';
    return units.isEmpty ? requested : units.first.code;
  }

  InventoryUnit? get baseUnit {
    for (final unit in units) {
      if (unit.code == baseCode) return unit;
    }
    return null;
  }

  InventoryUnit? unitById(String id) {
    for (final unit in units) {
      if (unit.id == id) return unit;
    }
    return null;
  }

  void setBaseCode(String value) {
    if (!units.any((unit) => unit.code == value)) return;
    baseCode = value;
    final selected = units.firstWhere((unit) => unit.code == value);
    baseStep = selected.allowFractional ? '0.1' : '1';
    baseCuttingAllowed = false;
    baseCuttingCharge = '0';
    rows.removeWhere((row) => unitById(row.unitId)?.code == value);
  }

  bool addAvailableUnit() {
    final used = rows.map((row) => row.unitId).toSet();
    final available = units
        .where((unit) => unit.code != baseCode && !used.contains(unit.id))
        .toList();
    if (available.isEmpty) return false;
    rows.add(ProductUnitDraft(unitId: available.first.id));
    return true;
  }

  String? validate() {
    if (units.isEmpty) return null;
    final base = baseUnit;
    if (base == null) return 'Select a valid base unit.';
    final baseQtyStep = double.tryParse(baseStep.trim());
    if (baseQtyStep == null || baseQtyStep <= 0) {
      return 'Base quantity step must be greater than zero.';
    }
    final baseCut = double.tryParse(baseCuttingCharge.trim());
    if (baseCut == null || baseCut < 0) {
      return 'Base cutting charge cannot be negative.';
    }
    final ids = <String>{};
    var defaultSaleCount = 0;
    var defaultPurchaseCount = 0;
    for (final row in rows) {
      if (!ids.add(row.unitId)) return 'The same unit cannot be configured twice.';
      if (unitById(row.unitId) == null) return 'One selected unit is no longer available.';
      final factor = double.tryParse(row.factor.trim());
      final step = double.tryParse(row.step.trim());
      if (factor == null || factor <= 0) return 'Unit conversion must be greater than zero.';
      if (step == null || step <= 0) return 'Unit quantity step must be greater than zero.';
      if (row.salePrice.trim().isNotEmpty) {
        final value = double.tryParse(row.salePrice.trim());
        if (value == null || value < 0) return 'Sale price must be zero or greater.';
      }
      if (row.purchaseCost.trim().isNotEmpty) {
        final value = double.tryParse(row.purchaseCost.trim());
        if (value == null || value < 0) return 'Purchase cost must be zero or greater.';
      }
      final cuttingCharge = double.tryParse(row.cuttingCharge.trim());
      if (cuttingCharge == null || cuttingCharge < 0) return 'Cutting charge cannot be negative.';
      if (row.defaultSale) {
        defaultSaleCount++;
        if (!row.allowSale) return 'Default sale unit must be enabled for sale.';
      }
      if (row.defaultPurchase) {
        defaultPurchaseCount++;
        if (!row.allowPurchase) return 'Default purchase unit must be enabled for purchase.';
      }
    }
    if (defaultSaleCount > 1) return 'Only one default sale unit can be selected.';
    if (defaultPurchaseCount > 1) return 'Only one default purchase unit can be selected.';
    return null;
  }

  List<Map<String, dynamic>> toPayload() {
    final base = baseUnit;
    return <Map<String, dynamic>>[
      if (base != null)
        <String, dynamic>{
          'unit_id': base.id,
          'quantity_step': double.tryParse(baseStep.trim()) ?? 1,
          'cutting_allowed': baseCuttingAllowed,
          'cutting_charge': double.tryParse(baseCuttingCharge.trim()) ?? 0,
        },
      ...rows.map((row) => row.toMap()),
    ];
  }

  static String _format(num value) {
    final d = value.toDouble();
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }
}

class ProductUnitDraft {
  ProductUnitDraft({
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

  factory ProductUnitDraft.fromOption(ProductUnitOption value) => ProductUnitDraft(
        unitId: value.unitId,
        factor: ProductUnitEditorController._format(value.conversionToBase),
        step: ProductUnitEditorController._format(value.quantityStep),
        salePrice: value.salePrice == null
            ? ''
            : ProductUnitEditorController._format(value.salePrice!),
        purchaseCost: value.purchaseCost == null
            ? ''
            : ProductUnitEditorController._format(value.purchaseCost!),
        cuttingCharge: ProductUnitEditorController._format(value.cuttingCharge),
        allowSale: value.allowSale,
        allowPurchase: value.allowPurchase,
        defaultSale: value.isDefaultSale,
        defaultPurchase: value.isDefaultPurchase,
        cuttingAllowed: value.cuttingAllowed,
        active: value.active,
      );

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

  Map<String, dynamic> toMap() => <String, dynamic>{
        'unit_id': unitId,
        'conversion_to_base': double.tryParse(factor.trim()) ?? 1,
        'quantity_step': double.tryParse(step.trim()) ?? 1,
        'sale_price': double.tryParse(salePrice.trim()),
        'purchase_cost': double.tryParse(purchaseCost.trim()),
        'cutting_allowed': cuttingAllowed,
        'cutting_charge': double.tryParse(cuttingCharge.trim()) ?? 0,
        'allow_sale': allowSale,
        'allow_purchase': allowPurchase,
        'is_default_sale': defaultSale,
        'is_default_purchase': defaultPurchase,
        'active': active,
      };
}

class ProductUnitEditor extends StatefulWidget {
  const ProductUnitEditor({
    super.key,
    required this.controller,
    this.enabled = true,
    this.currencySymbol = '₹',
  });

  final ProductUnitEditorController controller;
  final bool enabled;
  final String currencySymbol;

  @override
  State<ProductUnitEditor> createState() => _ProductUnitEditorState();
}

class _ProductUnitEditorState extends State<ProductUnitEditor> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (c.units.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Unit master could not be loaded. The base unit will be preserved.'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Units & conversions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Choose the stock base unit and every unit that can be used during sale or purchase.'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey<String>('product-base-${c.baseCode}'),
          initialValue: c.units.any((unit) => unit.code == c.baseCode) ? c.baseCode : null,
          decoration: const InputDecoration(labelText: 'Base inventory unit', border: OutlineInputBorder()),
          items: c.units
              .map((unit) => DropdownMenuItem<String>(value: unit.code, child: Text('${unit.name} (${unit.code})')))
              .toList(),
          onChanged: !widget.enabled
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => c.setBaseCode(value));
                },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            SizedBox(
              width: 180,
              child: TextFormField(
                key: ValueKey<String>('base-step-${c.baseCode}-${c.baseStep}'),
                initialValue: c.baseStep,
                enabled: widget.enabled,
                decoration: const InputDecoration(labelText: 'Base qty step', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) => c.baseStep = value,
              ),
            ),
            FilterChip(
              label: const Text('Cut / partial base qty'),
              selected: c.baseCuttingAllowed,
              onSelected: !widget.enabled ? null : (value) => setState(() => c.baseCuttingAllowed = value),
            ),
            if (c.baseCuttingAllowed)
              SizedBox(
                width: 190,
                child: TextFormField(
                  key: ValueKey<String>('base-cut-${c.baseCode}-${c.baseCuttingCharge}'),
                  initialValue: c.baseCuttingCharge,
                  enabled: widget.enabled,
                  decoration: InputDecoration(labelText: 'Cutting charge', prefixText: '${widget.currencySymbol} ', border: const OutlineInputBorder()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) => c.baseCuttingCharge = value,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(child: Text('Sale / purchase units', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            OutlinedButton.icon(
              onPressed: !widget.enabled
                  ? null
                  : () {
                      if (!c.addAvailableUnit()) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No more unused units are available.')));
                        return;
                      }
                      setState(() {});
                    },
              icon: const Icon(Icons.add),
              label: const Text('Add unit'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (c.rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No alternate units. Billing and purchasing will use the base unit.'),
          ),
        ...c.rows.asMap().entries.map((entry) => _row(entry.key, entry.value)),
      ],
    );
  }

  Widget _row(int index, ProductUnitDraft row) {
    final c = widget.controller;
    final candidates = c.units.where((unit) => unit.code != c.baseCode).toList();
    final unit = c.unitById(row.unitId);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey<String>('alt-unit-${row.unitId}-$index'),
                    initialValue: candidates.any((candidate) => candidate.id == row.unitId) ? row.unitId : null,
                    decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder()),
                    items: candidates
                        .map((candidate) => DropdownMenuItem<String>(value: candidate.id, child: Text('${candidate.name} (${candidate.code})')))
                        .toList(),
                    onChanged: !widget.enabled
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => row.unitId = value);
                          },
                  ),
                ),
                IconButton(
                  tooltip: 'Remove unit',
                  onPressed: !widget.enabled ? null : () => setState(() => c.rows.removeAt(index)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _numberField(
                  width: 180,
                  initial: row.factor,
                  label: '1 ${unit?.code ?? 'unit'} = base qty',
                  onChanged: (value) => row.factor = value,
                ),
                _numberField(width: 130, initial: row.step, label: 'Qty step', onChanged: (value) => row.step = value),
                _numberField(width: 170, initial: row.salePrice, label: 'Sale price / unit', onChanged: (value) => row.salePrice = value, optional: true),
                _numberField(width: 170, initial: row.purchaseCost, label: 'Purchase cost / unit', onChanged: (value) => row.purchaseCost = value, optional: true),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                FilterChip(label: const Text('Sale'), selected: row.allowSale, onSelected: !widget.enabled ? null : (value) => setState(() {row.allowSale = value;if (!value) row.defaultSale = false;})),
                FilterChip(label: const Text('Purchase'), selected: row.allowPurchase, onSelected: !widget.enabled ? null : (value) => setState(() {row.allowPurchase = value;if (!value) row.defaultPurchase = false;})),
                FilterChip(
                  label: const Text('Default sale'),
                  selected: row.defaultSale,
                  onSelected: !widget.enabled
                      ? null
                      : (value) => setState(() {
                            for (final candidate in c.rows) {candidate.defaultSale = false;}
                            row.defaultSale = value;
                            if (value) row.allowSale = true;
                          }),
                ),
                FilterChip(
                  label: const Text('Default purchase'),
                  selected: row.defaultPurchase,
                  onSelected: !widget.enabled
                      ? null
                      : (value) => setState(() {
                            for (final candidate in c.rows) {candidate.defaultPurchase = false;}
                            row.defaultPurchase = value;
                            if (value) row.allowPurchase = true;
                          }),
                ),
                FilterChip(label: const Text('Cut / partial'), selected: row.cuttingAllowed, onSelected: !widget.enabled ? null : (value) => setState(() => row.cuttingAllowed = value)),
              ],
            ),
            if (row.cuttingAllowed) ...<Widget>[
              const SizedBox(height: 10),
              _numberField(width: 190, initial: row.cuttingCharge, label: 'Cutting charge', onChanged: (value) => row.cuttingCharge = value, optional: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _numberField({
    required double width,
    required String initial,
    required String label,
    required ValueChanged<String> onChanged,
    bool optional = false,
  }) {
    return SizedBox(
      width: width,
      child: TextFormField(
        initialValue: initial,
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        onChanged: onChanged,
        validator: (value) {
          final text = value?.trim() ?? '';
          if (optional && text.isEmpty) return null;
          final parsed = double.tryParse(text);
          if (parsed == null || parsed < 0 || (!optional && parsed == 0)) return 'Invalid';
          return null;
        },
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
