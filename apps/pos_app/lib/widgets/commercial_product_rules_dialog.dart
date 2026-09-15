import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/inventory_product_detail.dart';
import '../services/commercial_pricing_service.dart';

class CommercialProductRulesDialog extends StatefulWidget {
  const CommercialProductRulesDialog({
    super.key,
    required this.session,
    required this.product,
  });

  final ClientSession session;
  final InventoryProductDetail product;

  @override
  State<CommercialProductRulesDialog> createState() =>
      _CommercialProductRulesDialogState();
}

class _CommercialProductRulesDialogState
    extends State<CommercialProductRulesDialog> {
  final CommercialPricingService _commercial = CommercialPricingService();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _catalog = const [];
  List<Map<String, dynamic>> _rules = const [];

  Map<String, dynamic>? get _serviceCharge {
    for (final row in _catalog) {
      if (row['service_variant_id']?.toString() == widget.product.variantId) {
        return row;
      }
    }
    return null;
  }

  String? get _locationId => widget.session.device?.locationId;
  String? get _deviceId => widget.session.device?.deviceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _number(dynamic value, [double fallback = 0]) =>
      (value as num?)?.toDouble() ?? double.tryParse('$value') ?? fallback;

  String _money(dynamic value) {
    final amount = _number(value);
    if (widget.session.currencyCode == 'INR') {
      return 'â‚¹${amount.toStringAsFixed(2)}';
    }
    return '${widget.session.currencyCode} ${amount.toStringAsFixed(2)}';
  }

  String _pretty(String value) => value
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part.substring(0, 1).toUpperCase()}${part.substring(1)}',
      )
      .join(' ');

  Future<void> _load() async {
    final locationId = _locationId;
    final deviceId = _deviceId;
    if (locationId == null || deviceId == null) {
      setState(() {
        _loading = false;
        _error = 'This POS is not activated to a location/device.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _commercial.chargeCatalog(
          tenantId: widget.session.business.id,
          locationId: locationId,
          deviceId: deviceId,
          activeOnly: false,
        ),
        _commercial.productChargeRules(
          tenantId: widget.session.business.id,
          locationId: locationId,
          deviceId: deviceId,
          productVariantId: widget.product.variantId,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _catalog = results[0];
        _rules = results[1];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editServiceCharge() async {
    if (widget.product.itemType != 'service') return;

    final existing = _serviceCharge;
    final quantity = TextEditingController(
      text: _number(existing?['default_quantity'], 1).toString(),
    );

    var enabled = existing?['active'] == true;
    var kind = existing?['charge_kind']?.toString() ?? 'packaging';
    var autoDineIn = existing?['auto_apply_dine_in'] == true;
    var autoTakeaway = existing?['auto_apply_takeaway'] == true;
    var autoDelivery = existing?['auto_apply_delivery'] == true;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? 'Register Commercial Charge'
                : 'Edit Commercial Charge',
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active commercial charge'),
                    subtitle: const Text(
                      'When active, this service can be used for Packaging, '
                      'Delivery, Service, Handling or Convenience charges.',
                    ),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: const InputDecoration(
                      labelText: 'Charge type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'packaging',
                        child: Text('Packaging'),
                      ),
                      DropdownMenuItem(
                        value: 'delivery',
                        child: Text('Delivery'),
                      ),
                      DropdownMenuItem(
                        value: 'service',
                        child: Text('Service'),
                      ),
                      DropdownMenuItem(
                        value: 'handling',
                        child: Text('Handling'),
                      ),
                      DropdownMenuItem(
                        value: 'convenience',
                        child: Text('Convenience'),
                      ),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => kind = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Default quantity',
                      helperText:
                          'Usually 1. Product rules can calculate separately.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Automatic order-type application',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      FilterChip(
                        selected: autoDineIn,
                        label: const Text('Dine-in'),
                        onSelected: (value) =>
                            setDialogState(() => autoDineIn = value),
                      ),
                      FilterChip(
                        selected: autoTakeaway,
                        label: const Text('Takeaway'),
                        onSelected: (value) =>
                            setDialogState(() => autoTakeaway = value),
                      ),
                      FilterChip(
                        selected: autoDelivery,
                        label: const Text('Delivery'),
                        onSelected: (value) =>
                            setDialogState(() => autoDelivery = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Selling price ${_money(widget.product.sellingPrice)} â€¢ '
                    'GST ${widget.product.taxRate.toStringAsFixed(2)}%',
                    style: Theme.of(context).textTheme.bodySmall,
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
            FilledButton.icon(
              onPressed: () async {
                final defaultQuantity =
                    double.tryParse(quantity.text.trim()) ?? 0;
                if (defaultQuantity <= 0) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Default quantity must be greater than 0.'),
                    ),
                  );
                  return;
                }

                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) {
      quantity.dispose();
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _commercial.saveChargeCatalog(
        tenantId: widget.session.business.id,
        locationId: _locationId!,
        deviceId: _deviceId!,
        chargeId: existing?['id']?.toString(),
        code: widget.product.sku,
        name: widget.product.productName,
        chargeKind: kind,
        serviceVariantId: widget.product.variantId,
        defaultQuantity: double.tryParse(quantity.text.trim()) ?? 1,
        autoDineIn: autoDineIn,
        autoTakeaway: autoTakeaway,
        autoDelivery: autoDelivery,
        active: enabled,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      quantity.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editRule([Map<String, dynamic>? existing]) async {
    final activeCatalog = _catalog
        .where((row) => row['active'] == true)
        .toList(growable: false);
    if (activeCatalog.isEmpty) {
      setState(
        () => _error =
            'Create at least one active commercial charge service first.',
      );
      return;
    }

    var chargeId =
        existing?['charge_catalog_id']?.toString() ??
        activeCatalog.first['id']?.toString() ??
        '';
    var orderType = existing?['order_type']?.toString() ?? 'delivery';
    var quantityMode = existing?['quantity_mode']?.toString() ?? 'per_unit';
    var active = existing?['active'] != false;
    final quantity = TextEditingController(
      text: _number(existing?['quantity_value'], 1).toString(),
    );

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? 'Add Charge Rule' : 'Edit Charge Rule',
          ),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: chargeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Commercial charge',
                      border: OutlineInputBorder(),
                    ),
                    items: activeCatalog
                        .map(
                          (row) => DropdownMenuItem(
                            value: row['id']?.toString(),
                            child: Text(
                              '${row['name'] ?? row['code']} â€¢ '
                              '${_pretty(row['charge_kind']?.toString() ?? 'other')} â€¢ '
                              '${_money(row['selling_price'])}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => chargeId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: orderType,
                    decoration: const InputDecoration(
                      labelText: 'Apply for',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All')),
                      DropdownMenuItem(
                        value: 'sale',
                        child: Text('Normal Sale'),
                      ),
                      DropdownMenuItem(
                        value: 'dine_in',
                        child: Text('Dine-in'),
                      ),
                      DropdownMenuItem(
                        value: 'takeaway',
                        child: Text('Takeaway'),
                      ),
                      DropdownMenuItem(
                        value: 'delivery',
                        child: Text('Delivery'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => orderType = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: quantityMode,
                    decoration: const InputDecoration(
                      labelText: 'Quantity calculation',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'per_unit',
                        child: Text('Per product unit'),
                      ),
                      DropdownMenuItem(
                        value: 'per_line',
                        child: Text('Per invoice line'),
                      ),
                      DropdownMenuItem(
                        value: 'fixed',
                        child: Text('Fixed once'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => quantityMode = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: quantityMode == 'per_unit'
                          ? 'Charge qty per product unit'
                          : quantityMode == 'per_line'
                          ? 'Charge qty per line'
                          : 'Fixed charge qty',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Rule active'),
                    value: active,
                    onChanged: (value) => setDialogState(() => active = value),
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
            FilledButton.icon(
              onPressed: () {
                final value = double.tryParse(quantity.text.trim()) ?? 0;
                if (chargeId.isEmpty || value <= 0) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Choose a charge and enter a quantity above 0.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Save Rule'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) {
      quantity.dispose();
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _commercial.saveProductChargeRule(
        tenantId: widget.session.business.id,
        locationId: _locationId!,
        deviceId: _deviceId!,
        ruleId: existing?['id']?.toString(),
        productVariantId: widget.product.variantId,
        chargeCatalogId: chargeId,
        orderType: orderType,
        quantityMode: quantityMode,
        quantityValue: double.tryParse(quantity.text.trim()) ?? 1,
        active: active,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      quantity.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleRule(Map<String, dynamic> rule, bool active) async {
    final id = rule['id']?.toString();
    final chargeId = rule['charge_catalog_id']?.toString();
    if (id == null || chargeId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _commercial.saveProductChargeRule(
        tenantId: widget.session.business.id,
        locationId: _locationId!,
        deviceId: _deviceId!,
        ruleId: id,
        productVariantId: widget.product.variantId,
        chargeCatalogId: chargeId,
        orderType: rule['order_type']?.toString() ?? 'delivery',
        quantityMode: rule['quantity_mode']?.toString() ?? 'per_unit',
        quantityValue: _number(rule['quantity_value'], 1),
        active: active,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _serviceChargeCard(BuildContext context) {
    final existing = _serviceCharge;
    final registered = existing != null;
    final active = existing?['active'] == true;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: active
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              child: Icon(
                Icons.add_card_outlined,
                color: active ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    registered
                        ? '${_pretty(existing['charge_kind']?.toString() ?? 'other')} Charge'
                        : 'Not registered as a commercial charge',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    registered
                        ? '${existing['code']} â€¢ ${_money(existing['selling_price'])} â€¢ '
                              '${existing['tax_rate']}% GST â€¢ ${active ? 'Active' : 'Inactive'}'
                        : 'Register this Service product so it can be selected '
                              'as Packaging, Delivery, Service or Handling charge.',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.tonalIcon(
              onPressed: _saving ? null : _editServiceCharge,
              icon: const Icon(Icons.tune_outlined, size: 16),
              label: Text(registered ? 'Configure' : 'Register'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rulesCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.rule_folder_outlined, size: 20),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    'Automatic Product Charge Rules',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _saving ? null : () => _editRule(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Rule'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Rules can apply a configured charge per product unit, per '
              'invoice line or once per order for normal Sale, Dine-in, '
              'Takeaway, Delivery or all order types.',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            if (_rules.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'No automatic charge rules are configured for this product.',
                ),
              )
            else
              ..._rules.map(
                (rule) => Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rule['charge_name']?.toString() ??
                                  rule['charge_code']?.toString() ??
                                  'Charge',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_pretty(rule['order_type']?.toString() ?? 'delivery')} â€¢ '
                              '${_pretty(rule['quantity_mode']?.toString() ?? 'per_unit')} â€¢ '
                              'Qty ${_number(rule['quantity_value'], 1)}',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: rule['active'] != false,
                        onChanged: _saving
                            ? null
                            : (value) => _toggleRule(rule, value),
                      ),
                      IconButton(
                        tooltip: 'Edit rule',
                        onPressed: _saving ? null : () => _editRule(rule),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 900,
        height: 680,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.price_change_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Commercial Pricing Rules',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${widget.product.productName} â€¢ ${widget.product.sku}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _saving ? null : _load,
                    icon: const Icon(Icons.refresh_outlined),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_saving) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(_error!),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (widget.product.itemType == 'service')
                            _serviceChargeCard(context),
                          if (widget.product.itemType == 'service')
                            const SizedBox(height: 8),
                          _rulesCard(context),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
