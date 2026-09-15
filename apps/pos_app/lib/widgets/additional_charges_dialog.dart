import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/commercial_pricing_service.dart';
import '../services/inventory_service.dart';

class AdditionalChargesDialog extends StatefulWidget {
  const AdditionalChargesDialog({
    super.key,
    required this.session,
    required this.locationId,
  });

  final ClientSession session;
  final String locationId;

  @override
  State<AdditionalChargesDialog> createState() =>
      _AdditionalChargesDialogState();
}

class _AdditionalChargesDialogState extends State<AdditionalChargesDialog> {
  final CommercialPricingService _commercial = CommercialPricingService();
  final InventoryService _inventory = InventoryService();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _charges = const [];

  String get _deviceId => widget.session.device?.deviceId ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _number(dynamic value) =>
      (value as num?)?.toDouble() ?? double.tryParse('$value') ?? 0.0;

  String _money(dynamic value) {
    final amount = _number(value);
    if (widget.session.currencyCode == 'INR') {
      return 'â‚¹${amount.toStringAsFixed(2)}';
    }
    return '${widget.session.currencyCode} ${amount.toStringAsFixed(2)}';
  }

  String _pretty(dynamic value) => (value?.toString() ?? 'other')
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part.substring(0, 1).toUpperCase()}${part.substring(1)}',
      )
      .join(' ');

  Future<void> _load() async {
    if (_deviceId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This POS is not activated to a terminal.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _commercial.chargeCatalog(
        tenantId: widget.session.business.id,
        locationId: widget.locationId,
        deviceId: _deviceId,
      );
      if (mounted) setState(() => _charges = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addCharge() async {
    final name = TextEditingController();
    final amount = TextEditingController(text: '0.00');
    final tax = TextEditingController(text: '0');
    var kind = 'packaging';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Additional Charge'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  isExpanded: true,
                  dropdownColor: Theme.of(context).colorScheme.surface,
                  decoration: const InputDecoration(labelText: 'Charge type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'packaging',
                      child: Text('Packaging'),
                    ),
                    DropdownMenuItem(
                      value: 'delivery',
                      child: Text('Delivery'),
                    ),
                    DropdownMenuItem(value: 'service', child: Text('Service')),
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
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Charge name',
                    hintText: 'Example: Packing Charge',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Default amount',
                          helperText: 'Editable again on every bill.',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: tax,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'GST / Tax %',
                          suffixText: '%',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final chargeName = name.text.trim();
                final defaultAmount = double.tryParse(amount.text.trim()) ?? -1;
                final taxRate = double.tryParse(tax.text.trim()) ?? -1;

                if (chargeName.isEmpty ||
                    defaultAmount < 0 ||
                    taxRate < 0 ||
                    taxRate > 100) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Enter a name, a non-negative amount and tax from 0 to 100.',
                      ),
                    ),
                  );
                  return;
                }

                Navigator.pop(dialogContext, <String, dynamic>{
                  'name': chargeName,
                  'kind': kind,
                  'amount': defaultAmount,
                  'tax_rate': taxRate,
                });
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Create Charge'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    amount.dispose();
    tax.dispose();

    if (result == null || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final sku = await _inventory.nextSku(
        tenantId: widget.session.business.id,
      );

      if (sku.trim().isEmpty) {
        throw StateError('Could not generate a SKU for the charge service.');
      }

      final created = await _inventory.createProduct(
        tenantId: widget.session.business.id,
        name: result['name'].toString(),
        sku: sku,
        itemType: 'service',
        description: 'THQ additional charge (${result['kind']})',
        categoryName: '',
        brandName: '',
        barcode: '',
        partNumber: '',
        costPrice: 0,
        sellingPrice: (result['amount'] as num).toDouble(),
        listPrice: null,
        taxRate: (result['tax_rate'] as num).toDouble(),
        reorderLevel: 0,
        openingStock: 0,
        locationId: widget.locationId,
        baseUnitCode: 'PCS',
        units: const <Map<String, dynamic>>[],
      );

      final variantId = created['variant_id']?.toString() ?? '';
      if (variantId.isEmpty) {
        throw StateError(
          'Charge service was created but its variant ID was not returned.',
        );
      }

      await _commercial.saveChargeCatalog(
        tenantId: widget.session.business.id,
        locationId: widget.locationId,
        deviceId: _deviceId,
        code: sku,
        name: result['name'].toString(),
        chargeKind: result['kind'].toString(),
        serviceVariantId: variantId,
        defaultQuantity: 1,
        autoDineIn: false,
        autoTakeaway: false,
        autoDelivery: false,
        active: true,
      );

      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 820,
        height: 620,
        child: Column(
          children: [
            Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.add_card_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Additional Charges',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Global billing charges available to POS and Restaurant.',
                          style: TextStyle(fontSize: 9.5),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _saving ? null : _addCharge,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Charge'),
                  ),
                  const SizedBox(width: 5),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _saving ? null : _load,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
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
                                color: scheme.errorContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(
                                alpha: .35,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'These are not tied to a particular product. '
                              'Every active charge appears in the Additional Charge '
                              'dropdown during billing. Its amount can be changed '
                              'for that invoice before GST is calculated.',
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_charges.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(28),
                              child: Center(
                                child: Text(
                                  'No additional charges have been created yet.',
                                ),
                              ),
                            )
                          else
                            ..._charges.map(
                              (charge) => Container(
                                margin: const EdgeInsets.only(bottom: 7),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: scheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.price_change_outlined,
                                        color: scheme.onPrimaryContainer,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            charge['name']?.toString() ??
                                                'Charge',
                                            style: TextStyle(
                                              color: scheme.onSurface,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          Text(
                                            '${_pretty(charge['charge_kind'])} â€¢ '
                                            'Default ${_money(charge['selling_price'])} â€¢ '
                                            'GST ${_number(charge['tax_rate']).toStringAsFixed(2)}%',
                                            style: TextStyle(
                                              color: scheme.onSurfaceVariant,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Chip(
                                      label: Text(
                                        charge['active'] == false
                                            ? 'INACTIVE'
                                            : 'ACTIVE',
                                      ),
                                    ),
                                  ],
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
    );
  }
}
