import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';

import '../models/client_session.dart';
import '../services/inventory_service.dart';

class AddProductScreen extends StatefulWidget {
  final ClientSession session;
  final String locationId;
  final String locationLabel;

  const AddProductScreen({
    super.key,
    required this.session,
    required this.locationId,
    required this.locationLabel,
  });

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();

  final InventoryService _service = InventoryService();

  final _nameController = TextEditingController();
  final _skuController = TextEditingController();
  final _descriptionController = TextEditingController();

  final _categoryController = TextEditingController();

  final _brandController = TextEditingController();

  final _barcodeController = TextEditingController();

  final _partNumberController = TextEditingController();

  final _costPriceController = TextEditingController(text: '0');

  final _sellingPriceController = TextEditingController(text: '0');

  final _listPriceController = TextEditingController();

  final _taxRateController = TextEditingController(text: '0');

  final _reorderController = TextEditingController(text: '0');

  final _openingStockController = TextEditingController(text: '0');

  String _itemType = 'stock';
  List<InventoryUnit> _units = const [];
  String _baseUnitCode = 'PCS';

  bool _saving = false;

  String? _error;

  double _number(TextEditingController controller) {
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  double? _optionalNumber(TextEditingController controller) {
    final text = controller.text.trim();

    if (text.isEmpty) {
      return null;
    }

    return double.tryParse(text);
  }

  String? _requiredText(String? value, String field) {
    if (value == null || value.trim().isEmpty) {
      return '$field is required.';
    }

    return null;
  }

  String? _nonNegativeNumber(String? value, String field) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return '$field is required.';
    }

    final number = double.tryParse(text);

    if (number == null) {
      return 'Enter a valid number.';
    }

    if (number < 0) {
      return '$field cannot be negative.';
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadNextSku();
    _loadUnits();
  }

  Future<void> _loadNextSku() async {
    try {
      final sku = await _service.nextSku(tenantId: widget.session.business.id);
      if (mounted && _skuController.text.trim().isEmpty) {
        setState(() => _skuController.text = sku);
      }
    } catch (_) {
      // SKU remains editable even if the helper cannot be reached.
    }
  }


  Future<void> _loadUnits() async {
    try {
      final units = await _service.getUnits(tenantId: widget.session.business.id);
      if (!mounted) return;
      setState(() {
        _units = units;
        final preferred = _itemType == 'service' ? 'HR' : _baseUnitCode;
        if (units.any((u) => u.code == preferred)) {
          _baseUnitCode = preferred;
        } else if (units.isNotEmpty) {
          _baseUnitCode = units.first.code;
        }
      });
    } catch (_) {
      // Product creation remains usable; PCS/HR are seeded by the backend.
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final taxRate = _number(_taxRateController);

    if (taxRate > 100) {
      setState(() {
        _error = 'Tax rate cannot be more than 100%.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final available = await _service.skuAvailable(
        tenantId: widget.session.business.id,
        sku: _skuController.text,
      );
      if (!available) {
        throw Exception(
          'SKU already exists. Choose another SKU or generate the next one.',
        );
      }
      await _service.createProduct(
        tenantId: widget.session.business.id,
        name: _nameController.text,
        sku: _skuController.text,
        itemType: _itemType,
        description: _descriptionController.text,
        categoryName: _categoryController.text,
        brandName: _brandController.text,
        barcode: _barcodeController.text,
        partNumber: _partNumberController.text,
        costPrice: _number(_costPriceController),
        sellingPrice: _number(_sellingPriceController),
        listPrice: _optionalNumber(_listPriceController),
        taxRate: taxRate,
        reorderLevel: _number(_reorderController),
        openingStock: _itemType == 'stock'
            ? _number(_openingStockController)
            : 0,
        locationId: widget.locationId,
        baseUnitCode: _baseUnitCode,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      var message = error.toString();

      if (message.startsWith('PostgrestException(message: ')) {
        // Leave Supabase message readable for now.
        message = message;
      }

      setState(() {
        _error = message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _brandController.dispose();
    _barcodeController.dispose();
    _partNumberController.dispose();
    _costPriceController.dispose();
    _sellingPriceController.dispose();
    _listPriceController.dispose();
    _taxRateController.dispose();
    _reorderController.dispose();
    _openingStockController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        title: const Text(
          'Add Product',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),

          child: Container(
            constraints: const BoxConstraints(maxWidth: 900),

            padding: const EdgeInsets.all(30),

            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),

            child: Form(
              key: _formKey,

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Product Information',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    'Create a product and assign its opening stock to one store.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),

                  const SizedBox(height: 10),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      avatar: const Icon(Icons.store_outlined, size: 17),
                      label: Text(widget.locationLabel),
                    ),
                  ),

                  const SizedBox(height: 20),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth > 650;

                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _nameField()),

                            const SizedBox(width: 16),

                            Expanded(child: _skuField()),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          _nameField(),

                          const SizedBox(height: 16),

                          _skuField(),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    initialValue: _itemType,
                    decoration: const InputDecoration(
                      labelText: 'Item Type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'stock',
                        child: Text('Stock Item'),
                      ),
                      DropdownMenuItem(
                        value: 'non_stock',
                        child: Text('Non-stock Item'),
                      ),
                      DropdownMenuItem(
                        value: 'service',
                        child: Text('Service / Labour'),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value == null) {
                              return;
                            }

                            setState(() {
                              _itemType = value;

                              if (_itemType != 'stock') {
                                _openingStockController.text = '0';
                              }
                              final preferred = _itemType == 'service' ? 'HR' : 'PCS';
                              if (_units.any((u) => u.code == preferred)) {
                                _baseUnitCode = preferred;
                              }
                            });
                          },
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _descriptionController,
                    enabled: !_saving,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 26),

                  const Text(
                    'Classification',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),

                  const SizedBox(height: 16),

                  _twoFields(
                    TextFormField(
                      controller: _categoryController,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        hintText: 'Starter Motor',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _brandController,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Brand',
                        hintText: 'Bosch',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 26),

                  const Text(
                    'Identification',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),

                  const SizedBox(height: 16),

                  _twoFields(
                    TextFormField(
                      controller: _barcodeController,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Barcode',
                        hintText: 'Optional',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _partNumberController,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Part Number',
                        hintText: '0001108157',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 26),

                  const Text(
                    'Inventory Unit',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),

                  const SizedBox(height: 8),

                  const Text('Stock is stored in the base unit. Add Box / Coil / Carton conversions from Product Details after saving.'),

                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    initialValue: _units.any((u) => u.code == _baseUnitCode) ? _baseUnitCode : null,
                    decoration: const InputDecoration(
                      labelText: 'Base Unit',
                      border: OutlineInputBorder(),
                    ),
                    items: _units
                        .map((u) => DropdownMenuItem(
                              value: u.code,
                              child: Text('${u.name} (${u.code})'),
                            ))
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _baseUnitCode = value ?? _baseUnitCode),
                  ),

                  const SizedBox(height: 26),

                  const Text(
                    'Pricing',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),

                  const SizedBox(height: 16),

                  _twoFields(
                    TextFormField(
                      controller: _costPriceController,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) =>
                          _nonNegativeNumber(value, 'Cost price'),
                      decoration: const InputDecoration(
                        labelText: 'Cost Price',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _sellingPriceController,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) =>
                          _nonNegativeNumber(value, 'Selling price'),
                      decoration: const InputDecoration(
                        labelText: 'Selling Price',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  _twoFields(
                    TextFormField(
                      controller: _listPriceController,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';

                        if (text.isEmpty) {
                          return null;
                        }

                        return _nonNegativeNumber(value, 'List price');
                      },
                      decoration: const InputDecoration(
                        labelText: 'MRP / List Price',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _taxRateController,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) =>
                          _nonNegativeNumber(value, 'Tax rate'),
                      decoration: const InputDecoration(
                        labelText: 'Tax Rate',
                        suffixText: '%',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 26),

                  const Text(
                    'Stock',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),

                  const SizedBox(height: 16),

                  _twoFields(
                    TextFormField(
                      controller: _reorderController,
                      enabled: !_saving && _itemType == 'stock',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) {
                        if (_itemType != 'stock') {
                          return null;
                        }

                        return _nonNegativeNumber(value, 'Reorder level');
                      },
                      decoration: InputDecoration(
                        labelText: 'Reorder Level',
                        suffixText: _baseUnitCode,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _openingStockController,
                      enabled: !_saving && _itemType == 'stock',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) {
                        if (_itemType != 'stock') {
                          return null;
                        }

                        return _nonNegativeNumber(value, 'Opening stock');
                      },
                      decoration: InputDecoration(
                        labelText: 'Opening Stock',
                        suffixText: _baseUnitCode,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 22),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade100),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],

                  const SizedBox(height: 30),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () {
                                Navigator.of(context).pop();
                              },
                        child: const Text('Cancel'),
                      ),

                      const SizedBox(width: 12),

                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_saving ? 'Saving...' : 'Save Product'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _nameField() {
    return TextFormField(
      controller: _nameController,
      enabled: !_saving,
      autofocus: true,
      validator: (value) => _requiredText(value, 'Product name'),
      decoration: const InputDecoration(
        labelText: 'Product Name',
        hintText: 'Bosch Starter Motor',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _skuField() {
    return TextFormField(
      controller: _skuController,
      enabled: !_saving,
      validator: (value) => _requiredText(value, 'SKU'),
      decoration: InputDecoration(
        labelText: 'SKU',
        hintText: 'SKU-000001',
        helperText:
            'Generated automatically. You can edit it, but it must stay unique.',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: 'Generate next SKU',
          onPressed: _saving ? null : _loadNextSku,
          icon: const Icon(Icons.auto_awesome_outlined),
        ),
      ),
    );
  }

  Widget _twoFields(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 650) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 16),
              Expanded(child: second),
            ],
          );
        }

        return Column(children: [first, const SizedBox(height: 16), second]);
      },
    );
  }
}
