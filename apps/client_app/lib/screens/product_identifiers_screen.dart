import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/supplier.dart';
import '../services/label_printing_service.dart';
import '../services/product_identification_service.dart';
import '../services/supplier_service.dart';
import '../widgets/searchable_select.dart';

class ProductIdentifiersScreen extends StatefulWidget {
  final ClientSession session;
  final String variantId;
  final String productName;
  final String sku;
  final double sellingPrice;

  const ProductIdentifiersScreen({
    super.key,
    required this.session,
    required this.variantId,
    required this.productName,
    required this.sku,
    required this.sellingPrice,
  });

  @override
  State<ProductIdentifiersScreen> createState() => _ProductIdentifiersScreenState();
}

class _ProductIdentifiersScreenState extends State<ProductIdentifiersScreen> {
  final ProductIdentificationService _service = ProductIdentificationService();
  final SupplierService _suppliersService = SupplierService();
  final LabelPrintingService _labels = LabelPrintingService();

  bool _loading = true;
  String? _error;
  List<ProductIdentifier> _identifiers = const [];
  List<Supplier> _suppliers = const [];
  List<Map<String, dynamic>> _templates = const [];
  String? _templateId;
  int _copies = 1;
  bool _printing = false;

  bool get _canManage => widget.session.hasPermission('inventory.manage') || widget.session.hasRole('owner');

  @override
  void initState() {
    super.initState();
    _load();
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
        _service.identifiers(tenantId: widget.session.business.id, variantId: widget.variantId),
        _suppliersService.getSuppliers(tenantId: widget.session.business.id),
        _service.labelTemplates(widget.session.business.id),
      ]);
      if (!mounted) return;
      final ids = results[0] as List<ProductIdentifier>;
      final suppliers = results[1] as List<Supplier>;
      final templates = results[2] as List<Map<String, dynamic>>;
      var templateId = _templateId;
      if (templateId == null || !templates.any((e) => e['id']?.toString() == templateId)) {
        final defaults = templates.where((e) => e['is_default'] == true).toList();
        templateId = (defaults.isNotEmpty ? defaults.first : (templates.isNotEmpty ? templates.first : null))?['id']?.toString();
      }
      setState(() {
        _identifiers = ids;
        _suppliers = suppliers;
        _templates = templates;
        _templateId = templateId;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _typeLabel(String type) => switch (type) {
        'barcode' => 'Barcode',
        'qr' => 'QR Code',
        'manufacturer' => 'Manufacturer Code',
        'supplier' => 'Supplier Code',
        'internal' => 'Internal Code',
        'alternate_sku' => 'Alternate SKU',
        _ => type,
      };

  IconData _typeIcon(String type) => switch (type) {
        'barcode' => Icons.view_week_outlined,
        'qr' => Icons.qr_code_2_outlined,
        'manufacturer' => Icons.factory_outlined,
        'supplier' => Icons.local_shipping_outlined,
        'internal' => Icons.tag_outlined,
        'alternate_sku' => Icons.alternate_email,
        _ => Icons.numbers,
      };

  Future<void> _generate(String type) async {
    if (!_canManage) return;
    try {
      final identifier = await _service.generate(
        tenantId: widget.session.business.id,
        variantId: widget.variantId,
        type: type,
      );
      if (!mounted) return;
      _message('${_typeLabel(type)} generated: ${identifier.code}');
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _edit([ProductIdentifier? current]) async {
    if (!_canManage) return;
    var type = current?.type ?? 'barcode';
    var supplierId = current?.supplierId;
    var isPrimary = current?.isPrimary ?? false;
    var active = current?.active ?? true;
    final code = TextEditingController(text: current?.code ?? '');
    final label = TextEditingController(text: current?.label ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(current == null ? 'Add Product Identifier' : 'Edit Product Identifier'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Identifier Type'),
                  items: const [
                    DropdownMenuItem(value: 'barcode', child: Text('Barcode')),
                    DropdownMenuItem(value: 'qr', child: Text('QR Code')),
                    DropdownMenuItem(value: 'manufacturer', child: Text('Manufacturer Code')),
                    DropdownMenuItem(value: 'supplier', child: Text('Supplier Code')),
                    DropdownMenuItem(value: 'internal', child: Text('Internal Code')),
                    DropdownMenuItem(value: 'alternate_sku', child: Text('Alternate SKU')),
                  ],
                  onChanged: (value) => setDialogState(() {
                    type = value ?? 'barcode';
                    if (type != 'supplier') supplierId = null;
                  }),
                ),
                const SizedBox(height: 10),
                TextField(controller: code, decoration: const InputDecoration(labelText: 'Code')),
                const SizedBox(height: 10),
                if (type == 'supplier')
                  SearchableSelect<String>(
                    value: supplierId,
                    labelText: 'Supplier',
                    allowClear: true,
                    hintText: 'Search supplier name, ID, phone or GSTIN',
                    prefixIcon: Icons.local_shipping_outlined,
                    options: _suppliers.where((e) => e.isActive).map((supplier) => SearchableSelectOption<String>(
                      value: supplier.id,
                      label: supplier.name,
                      subtitle: [supplier.publicId, supplier.phone, supplier.taxNumber].whereType<String>().where((v) => v.trim().isNotEmpty).join(' • '),
                      searchText: '${supplier.name} ${supplier.publicId} ${supplier.phone ?? ''} ${supplier.email ?? ''} ${supplier.taxNumber ?? ''}',
                    )).toList(),
                    onChanged: (value) => setDialogState(() => supplierId = value),
                  ),
                if (type == 'supplier') const SizedBox(height: 10),
                TextField(controller: label, decoration: const InputDecoration(labelText: 'Label / Note')),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isPrimary,
                  onChanged: (value) => setDialogState(() => isPrimary = value),
                  title: const Text('Primary identifier of this type'),
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
                if (code.text.trim().isEmpty) return;
                try {
                  await _service.save(
                    tenantId: widget.session.business.id,
                    variantId: widget.variantId,
                    identifierId: current?.id,
                    type: type,
                    code: code.text,
                    supplierId: supplierId,
                    label: label.text,
                    isPrimary: isPrimary,
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
    label.dispose();
    if (!mounted) return;
    if (saved == true) await _load();
  }

  Future<void> _archive(ProductIdentifier identifier) async {
    if (!_canManage) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive identifier?'),
        content: Text('${_typeLabel(identifier.type)}\n${identifier.code}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Archive')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await _service.archive(tenantId: widget.session.business.id, identifierId: identifier.id);
      if (!mounted) return;
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _print(ProductIdentifier identifier) async {
    final template = _templates.where((e) => e['id']?.toString() == _templateId).cast<Map<String, dynamic>?>().firstOrNull;
    if (template == null) {
      _message('No label template is available.');
      return;
    }
    setState(() => _printing = true);
    try {
      final currency = widget.session.currencyCode;
      final price = currency == 'INR'
          ? '₹${widget.sellingPrice.toStringAsFixed(2)}'
          : '$currency ${widget.sellingPrice.toStringAsFixed(2)}';
      await _labels.printLabels(
        template: template,
        copies: _copies,
        label: ProductLabelData(
          businessName: widget.session.business.name,
          productName: widget.productName,
          sku: widget.sku,
          code: identifier.code,
          codeMode: identifier.type == 'qr' ? 'qr' : 'barcode',
          priceText: price,
        ),
      );
    } catch (error) {
      _message('Label printing failed: $error');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Codes & Labels • ${widget.productName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), const SizedBox(height: 12), OutlinedButton(onPressed: _load, child: const Text('Retry'))]))
              : Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('SKU ${widget.sku}', style: const TextStyle(fontWeight: FontWeight.w800)),
                              if (_canManage)
                                FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add Code')),
                              if (_canManage)
                                OutlinedButton.icon(onPressed: () => _generate('barcode'), icon: const Icon(Icons.view_week_outlined), label: const Text('Generate Barcode')),
                              if (_canManage)
                                OutlinedButton.icon(onPressed: () => _generate('qr'), icon: const Icon(Icons.qr_code_2_outlined), label: const Text('Generate QR')),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _templateId,
                                  decoration: const InputDecoration(labelText: 'Label Template'),
                                  items: _templates.map((t) => DropdownMenuItem(value: t['id']?.toString(), child: Text(t['name']?.toString() ?? 'Label'))).toList(),
                                  onChanged: (value) => setState(() => _templateId = value),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 120,
                                child: DropdownButtonFormField<int>(
                                  initialValue: _copies,
                                  decoration: const InputDecoration(labelText: 'Copies'),
                                  items: const [1, 2, 3, 5, 10, 20, 50].map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(),
                                  onChanged: (value) => setState(() => _copies = value ?? 1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Card(
                          child: _identifiers.isEmpty
                              ? const Center(child: Text('No identifiers yet. Add a barcode, QR, manufacturer code, supplier code, internal code or alternate SKU.'))
                              : ListView.separated(
                                  itemCount: _identifiers.length,
                                  separatorBuilder: (_, _) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final id = _identifiers[index];
                                    return ListTile(
                                      leading: CircleAvatar(child: Icon(_typeIcon(id.type))),
                                      title: SelectableText(id.code, style: const TextStyle(fontWeight: FontWeight.w800)),
                                      subtitle: Text('${_typeLabel(id.type)}${id.supplierName?.isNotEmpty == true ? ' • ${id.supplierName}' : ''}${id.isPrimary ? ' • PRIMARY' : ''}${!id.active ? ' • ARCHIVED' : ''}${id.label?.isNotEmpty == true ? '\n${id.label}' : ''}'),
                                      isThreeLine: id.label?.isNotEmpty == true,
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (id.active && (id.type == 'barcode' || id.type == 'qr'))
                                            IconButton(onPressed: _printing ? null : () => _print(id), icon: const Icon(Icons.print_outlined), tooltip: 'Print label'),
                                          if (_canManage)
                                            IconButton(onPressed: () => _edit(id), icon: const Icon(Icons.edit_outlined), tooltip: 'Edit'),
                                          if (_canManage && id.active)
                                            IconButton(onPressed: () => _archive(id), icon: const Icon(Icons.archive_outlined), tooltip: 'Archive'),
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

extension _IdentifierFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
