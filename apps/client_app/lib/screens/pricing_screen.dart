import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/customer.dart';
import '../models/inventory_product.dart';
import '../services/customer_service.dart';
import '../services/inventory_service.dart';
import '../services/pricing_service.dart';

class PricingScreen extends StatefulWidget {
  final ClientSession session;
  const PricingScreen({super.key, required this.session});

  @override
  State<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends State<PricingScreen>
    with SingleTickerProviderStateMixin {
  final PricingService _pricing = PricingService();
  final InventoryService _inventory = InventoryService();
  final CustomerService _customersService = CustomerService();
  late final TabController _tabs;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _lists = const [];
  List<InventoryProduct> _products = const [];
  List<Customer> _customers = const [];
  String? _selectedListId;
  String? _selectedCustomerId;
  List<Map<String, dynamic>> _listRules = const [];
  List<Map<String, dynamic>> _customerRules = const [];

  bool get _canManage => widget.session.hasPermission('inventory.manage') ||
      widget.session.hasPermission('sales.manage') ||
      widget.session.hasRole('owner');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _pricing.priceLists(widget.session.business.id),
        _inventory.getProducts(tenantId: widget.session.business.id),
        _customersService.getCustomers(tenantId: widget.session.business.id),
      ]);
      if (!mounted) return;
      final lists = results[0] as List<Map<String, dynamic>>;
      final products = results[1] as List<InventoryProduct>;
      final customers = results[2] as List<Customer>;
      var listId = _selectedListId;
      if (listId == null || !lists.any((e) => e['price_list_id']?.toString() == listId)) {
        final active = lists.where((e) => e['active'] != false).toList();
        final preferred = active.where((e) => e['is_default'] == true).toList();
        listId = (preferred.isNotEmpty ? preferred.first : (active.isNotEmpty ? active.first : null))?['price_list_id']?.toString();
      }
      var customerId = _selectedCustomerId;
      if (customerId == null || !customers.any((e) => e.id == customerId)) {
        final nonWalkIn = customers.where((e) => !e.isWalkIn && e.isActive).toList();
        customerId = nonWalkIn.isEmpty ? null : nonWalkIn.first.id;
      }
      setState(() {
        _lists = lists;
        _products = products;
        _customers = customers;
        _selectedListId = listId;
        _selectedCustomerId = customerId;
      });
      await _loadRules();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRules() async {
    final listId = _selectedListId;
    final customerId = _selectedCustomerId;
    try {
      final results = await Future.wait([
        if (listId != null)
          _pricing.priceRules(
            tenantId: widget.session.business.id,
            priceListId: listId,
          )
        else
          Future.value(<Map<String, dynamic>>[]),
        if (customerId != null)
          _pricing.customerPrices(
            tenantId: widget.session.business.id,
            customerId: customerId,
          )
        else
          Future.value(<Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _listRules = results[0];
        _customerRules = results[1];
      });
    } catch (error) {
      _message('Could not refresh pricing rules: $error');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _money(dynamic value) {
    final amount = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    return widget.session.currencyCode == 'INR'
        ? '₹${amount.toStringAsFixed(2)}'
        : '${widget.session.currencyCode} ${amount.toStringAsFixed(2)}';
  }

  Future<void> _editList([Map<String, dynamic>? current]) async {
    if (!_canManage) return;
    final code = TextEditingController(text: current?['code']?.toString() ?? '');
    final name = TextEditingController(text: current?['name']?.toString() ?? '');
    final description = TextEditingController(text: current?['description']?.toString() ?? '');
    var isDefault = current?['is_default'] == true;
    var active = current?['active'] != false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(current == null ? 'Add Price List' : 'Edit Price List'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: code, decoration: const InputDecoration(labelText: 'Code', hintText: 'WHOLESALE')),
                const SizedBox(height: 10),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name', hintText: 'Wholesale')),
                const SizedBox(height: 10),
                TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isDefault,
                  onChanged: (value) => setDialogState(() => isDefault = value),
                  title: const Text('Default price list'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  onChanged: (value) => setDialogState(() => active = value),
                  title: const Text('Active'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (code.text.trim().isEmpty || name.text.trim().isEmpty) return;
                try {
                  await _pricing.savePriceList(
                    tenantId: widget.session.business.id,
                    priceListId: current?['price_list_id']?.toString(),
                    code: code.text,
                    name: name.text,
                    description: description.text,
                    isDefault: isDefault,
                    active: active,
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(error.toString())));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    code.dispose();
    name.dispose();
    description.dispose();
    if (!mounted) return;
    if (saved == true) await _load();
  }

  Future<void> _editRule({
    required bool customerSpecific,
    Map<String, dynamic>? current,
  }) async {
    if (!_canManage || _products.isEmpty) return;
    var variantId = current?['variant_id']?.toString() ?? _products.first.variantId;
    InventoryProduct productFor(String id) => _products.firstWhere((e) => e.variantId == id, orElse: () => _products.first);
    var product = productFor(variantId);
    var unitId = current?['unit_id']?.toString() ?? product.defaultSaleUnit?.unitId ?? (product.saleUnits.isNotEmpty ? product.saleUnits.first.unitId : '');
    final qty = TextEditingController(text: current?['min_quantity']?.toString() ?? '1');
    final price = TextEditingController(text: current?['unit_price']?.toString() ?? product.sellingPrice.toStringAsFixed(2));
    var active = current?['active'] != false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          product = productFor(variantId);
          final units = product.saleUnits;
          if (units.isNotEmpty && !units.any((e) => e.unitId == unitId)) {
            unitId = product.defaultSaleUnit?.unitId ?? units.first.unitId;
          }
          return AlertDialog(
            title: Text(customerSpecific ? 'Customer Specific Price' : 'Price Rule'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: variantId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Product'),
                    items: _products.map((p) => DropdownMenuItem(value: p.variantId, child: Text('${p.productName} • ${p.sku}', overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        variantId = value;
                        final next = productFor(value);
                        unitId = next.defaultSaleUnit?.unitId ?? (next.saleUnits.isNotEmpty ? next.saleUnits.first.unitId : '');
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: units.any((e) => e.unitId == unitId) ? unitId : null,
                    decoration: const InputDecoration(labelText: 'Sale Unit'),
                    items: units.map((u) => DropdownMenuItem(value: u.unitId, child: Text('${u.name} (${u.code})'))).toList(),
                    onChanged: (value) => setDialogState(() => unitId = value ?? ''),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Minimum Quantity'))),
                      const SizedBox(width: 10),
                      Expanded(child: TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Unit Price'))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (value) => setDialogState(() => active = value), title: const Text('Active')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final minQty = double.tryParse(qty.text.trim());
                  final unitPrice = double.tryParse(price.text.trim());
                  if (unitId.isEmpty || minQty == null || minQty <= 0 || unitPrice == null || unitPrice < 0) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Choose a valid product/unit, quantity and price.')));
                    return;
                  }
                  try {
                    if (customerSpecific) {
                      final customerId = _selectedCustomerId;
                      if (customerId == null) throw StateError('Select a customer first.');
                      await _pricing.saveCustomerPrice(
                        tenantId: widget.session.business.id,
                        ruleId: current?['rule_id']?.toString(),
                        customerId: customerId,
                        variantId: variantId,
                        unitId: unitId,
                        minQuantity: minQty,
                        unitPrice: unitPrice,
                        active: active,
                      );
                    } else {
                      final listId = _selectedListId;
                      if (listId == null) throw StateError('Select a price list first.');
                      await _pricing.savePriceRule(
                        tenantId: widget.session.business.id,
                        ruleId: current?['rule_id']?.toString(),
                        priceListId: listId,
                        variantId: variantId,
                        unitId: unitId,
                        minQuantity: minQty,
                        unitPrice: unitPrice,
                        active: active,
                      );
                    }
                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext, true);
                  } catch (error) {
                    if (!dialogContext.mounted) return;
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    qty.dispose();
    price.dispose();
    if (!mounted) return;
    if (saved == true) await _loadRules();
  }

  Future<void> _setCustomerPriceList(String? priceListId) async {
    final customerId = _selectedCustomerId;
    if (!_canManage || customerId == null) return;
    try {
      await _pricing.setCustomerPriceList(
        tenantId: widget.session.business.id,
        customerId: customerId,
        priceListId: priceListId,
      );
      if (!mounted) return;
      await _load();
      _message(priceListId == null ? 'Customer now uses the default retail price list.' : 'Customer price list updated.');
    } catch (error) {
      _message(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ]),
      );
    }
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(icon: Icon(Icons.sell_outlined), text: 'Price Lists'),
              Tab(icon: Icon(Icons.person_pin_outlined), text: 'Customer Pricing'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [_buildPriceLists(), _buildCustomerPricing()],
          ),
        ),
      ],
    );
  }

  Widget _buildPriceLists() {
    final selected = _lists.where((e) => e['price_list_id']?.toString() == _selectedListId).cast<Map<String, dynamic>?>().firstOrNull;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 280,
            child: Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Price Lists', style: TextStyle(fontWeight: FontWeight.w800)),
                    trailing: _canManage ? IconButton(onPressed: () => _editList(), icon: const Icon(Icons.add), tooltip: 'Add price list') : null,
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      children: _lists.map((list) {
                        final id = list['price_list_id']?.toString();
                        return ListTile(
                          selected: id == _selectedListId,
                          title: Text(list['name']?.toString() ?? ''),
                          subtitle: Text('${list['code'] ?? ''}${list['is_default'] == true ? ' • DEFAULT' : ''}${list['active'] == false ? ' • INACTIVE' : ''}'),
                          onTap: () async {
                            setState(() => _selectedListId = id);
                            await _loadRules();
                          },
                          trailing: _canManage ? IconButton(onPressed: () => _editList(list), icon: const Icon(Icons.edit_outlined), tooltip: 'Edit') : null,
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Card(
              child: Column(
                children: [
                  ListTile(
                    title: Text(selected?['name']?.toString() ?? 'Select a price list', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const Text('Quantity breaks use the greatest minimum quantity that matches the sale.'),
                    trailing: _canManage && _selectedListId != null ? FilledButton.icon(onPressed: () => _editRule(customerSpecific: false), icon: const Icon(Icons.add), label: const Text('Add Price')) : null,
                  ),
                  const Divider(height: 1),
                  Expanded(child: _ruleList(_listRules, customerSpecific: false)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerPricing() {
    final customers = _customers.where((e) => !e.isWalkIn).toList();
    final customer = customers.where((e) => e.id == _selectedCustomerId).cast<Customer?>().firstOrNull;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 300,
            child: Card(
              child: Column(
                children: [
                  const ListTile(title: Text('Customers', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('Assign a price list or create exact customer prices.')),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      children: customers.map((c) => ListTile(
                        selected: c.id == _selectedCustomerId,
                        title: Text(c.name),
                        subtitle: Text(c.priceListName?.isNotEmpty == true ? c.priceListName! : 'Default Retail'),
                        onTap: () async {
                          setState(() => _selectedCustomerId = c.id);
                          await _loadRules();
                        },
                      )).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Card(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: customer?.priceListId,
                            decoration: const InputDecoration(labelText: 'Assigned Price List'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('Default Retail')),
                              ..._lists.where((e) => e['active'] != false).map((list) => DropdownMenuItem<String?>(value: list['price_list_id']?.toString(), child: Text(list['name']?.toString() ?? ''))),
                            ],
                            onChanged: _canManage && customer != null ? _setCustomerPriceList : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (_canManage && customer != null)
                          FilledButton.icon(onPressed: () => _editRule(customerSpecific: true), icon: const Icon(Icons.add), label: const Text('Specific Price')),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: _ruleList(_customerRules, customerSpecific: true)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleList(List<Map<String, dynamic>> rules, {required bool customerSpecific}) {
    if (rules.isEmpty) {
      return const Center(child: Text('No pricing rules yet.'));
    }
    return ListView.separated(
      itemCount: rules.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final rule = rules[index];
        return ListTile(
          title: Text('${rule['product_name'] ?? ''} • ${rule['unit_code'] ?? ''}'),
          subtitle: Text('From qty ${rule['min_quantity'] ?? 1}${rule['active'] == false ? ' • INACTIVE' : ''}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_money(rule['unit_price']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              if (_canManage) ...[
                const SizedBox(width: 8),
                IconButton(onPressed: () => _editRule(customerSpecific: customerSpecific, current: rule), icon: const Icon(Icons.edit_outlined), tooltip: 'Edit'),
              ],
            ],
          ),
        );
      },
    );
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
