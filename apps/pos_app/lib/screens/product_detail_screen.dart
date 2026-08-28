import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/inventory_product_detail.dart';
import '../models/stock_movement.dart';
import '../services/inventory_service.dart';

class ProductDetailScreen extends StatefulWidget {
  final ClientSession session;
  final String variantId;

  const ProductDetailScreen({
    super.key,
    required this.session,
    required this.variantId,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final InventoryService _service = InventoryService();

  bool _loading = true;

  String? _error;

  InventoryProductDetail? _product;

  String? _publicId;

  List<StockMovement> _movements = [];

  bool get _canManage => widget.session.hasPermission('inventory.manage');

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
      final product = await _service.getProductDetail(
        tenantId: widget.session.business.id,
        variantId: widget.variantId,
      );
      final results = await Future.wait([
        _service.getStockMovements(
          tenantId: widget.session.business.id,
          variantId: widget.variantId,
        ),
        _service.publicId(
          tenantId: widget.session.business.id,
          entityType: 'product',
          entityId: product.productId,
        ),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _product = product;
        _movements = results[0] as List<StockMovement>;
        _publicId = results[1] as String?;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = _cleanError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _cleanError(Object error) {
    var message = error.toString();

    if (message.startsWith('Exception: ')) {
      message = message.substring(11);
    }

    return message;
  }

  String _money(double value) {
    if (widget.session.currencyCode == 'INR') {
      return '₹${value.toStringAsFixed(2)}';
    }

    return '${widget.session.currencyCode} '
        '${value.toStringAsFixed(2)}';
  }

  String _quantity(double value) {
    if (value % 1 == 0) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  String _date(DateTime? value) {
    if (value == null) {
      return '-';
    }

    final local = value.toLocal();

    final day = local.day.toString().padLeft(2, '0');

    final month = local.month.toString().padLeft(2, '0');

    final hour = local.hour.toString().padLeft(2, '0');

    final minute = local.minute.toString().padLeft(2, '0');

    return '$day-$month-${local.year} '
        '$hour:$minute';
  }

  String _movementName(String type) {
    switch (type) {
      case 'opening':
        return 'Opening Stock';

      case 'purchase':
        return 'Purchase';

      case 'sale':
        return 'Sale';

      case 'sale_return':
        return 'Sale Return';

      case 'purchase_return':
        return 'Purchase Return';

      case 'adjustment_in':
        return 'Stock Added';

      case 'adjustment_out':
        return 'Stock Removed';

      case 'transfer_in':
        return 'Transfer In';

      case 'transfer_out':
        return 'Transfer Out';

      default:
        return type;
    }
  }

  Future<void> _editProduct() async {
    final product = _product;

    if (product == null) {
      return;
    }

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _EditProductDialog(session: widget.session, product: product),
    );

    if (changed == true) {
      await _load();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product updated successfully.')),
      );
    }
  }

  Future<void> _adjustStock() async {
    final product = _product;

    if (product == null) {
      return;
    }

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _StockAdjustmentDialog(session: widget.session, product: product),
    );

    if (changed == true) {
      await _load();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock adjusted successfully.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        title: const Text(
          'Product Details',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        actions: [
          if (_canManage && _product != null)
            IconButton(
              tooltip: 'Edit Product',
              onPressed: _editProduct,
              icon: const Icon(Icons.edit_outlined),
            ),

          const SizedBox(width: 8),
        ],
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError()
          : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 58),

          const SizedBox(height: 16),

          Text(
            _error ?? 'Could not load product.',
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),

          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final product = _product!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),

      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(product),

              const SizedBox(height: 22),

              _buildInfoCard(product),

              const SizedBox(height: 22),

              _buildPricingCard(product),

              const SizedBox(height: 22),

              _buildStockCard(product),

              const SizedBox(height: 28),

              _buildMovementHistory(product),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(InventoryProductDetail product) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.inventory_2_outlined, size: 34),
        ),

        const SizedBox(width: 18),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.productName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                [product.brandName, product.categoryName]
                    .where((value) => value != null && value.isNotEmpty)
                    .join(' • '),
                style: TextStyle(color: Colors.grey.shade600),
              ),

              if (product.description != null &&
                  product.description!.isNotEmpty) ...[
                const SizedBox(height: 8),

                Text(product.description!),
              ],
            ],
          ),
        ),

        if (_canManage)
          FilledButton.icon(
            onPressed: _editProduct,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit Product'),
          ),
      ],
    );
  }

  Widget _buildInfoCard(InventoryProductDetail product) {
    return _SectionCard(
      title: 'Product Information',

      child: Wrap(
        spacing: 45,
        runSpacing: 22,
        children: [
          _InfoItem(
            label: 'Product ID',
            value: (_publicId == null || _publicId!.isEmpty) ? '-' : _publicId!,
          ),
          _InfoItem(label: 'SKU', value: product.sku),
          _InfoItem(label: 'Product ID', value: product.productId),
          _InfoItem(label: 'Variant ID', value: product.variantId),

          _InfoItem(label: 'Part Number', value: product.partNumber ?? '-'),

          _InfoItem(label: 'Barcode', value: product.barcode ?? '-'),

          _InfoItem(
            label: 'Item Type',
            value: product.itemType.replaceAll('_', ' ').toUpperCase(),
          ),

          _InfoItem(
            label: 'Unit',
            value: product.unitName ?? product.unitCode ?? '-',
          ),

          _InfoItem(
            label: 'Tax',
            value: '${product.taxRate.toStringAsFixed(2)}%',
          ),

          _InfoItem(label: 'Created', value: _date(product.createdAt)),

          _InfoItem(label: 'Updated', value: _date(product.updatedAt)),
        ],
      ),
    );
  }

  Widget _buildPricingCard(InventoryProductDetail product) {
    return _SectionCard(
      title: 'Pricing',

      child: Wrap(
        spacing: 60,
        runSpacing: 20,
        children: [
          _LargeValue(label: 'Cost Price', value: _money(product.costPrice)),

          _LargeValue(
            label: 'Selling Price',
            value: _money(product.sellingPrice),
          ),

          _LargeValue(
            label: 'MRP / List Price',
            value: product.listPrice == null ? '-' : _money(product.listPrice!),
          ),
        ],
      ),
    );
  }

  Widget _buildStockCard(InventoryProductDetail product) {
    final isStock = product.itemType == 'stock';

    final lowStock =
        isStock &&
        product.reorderLevel > 0 &&
        product.stockQuantity <= product.reorderLevel;

    return _SectionCard(
      title: 'Stock',

      trailing: _canManage && isStock
          ? FilledButton.icon(
              onPressed: _adjustStock,
              icon: const Icon(Icons.tune),
              label: const Text('Adjust Stock'),
            )
          : null,

      child: Wrap(
        spacing: 60,
        runSpacing: 20,
        children: [
          _LargeValue(
            label: 'Current Stock',
            value: isStock
                ? '${_quantity(product.stockQuantity)} '
                      '${product.unitCode ?? ''}'
                : 'Not Tracked',
          ),

          _LargeValue(
            label: 'Reorder Level',
            value: isStock
                ? '${_quantity(product.reorderLevel)} '
                      '${product.unitCode ?? ''}'
                : '-',
          ),

          if (lowStock)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'LOW STOCK',
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMovementHistory(InventoryProductDetail product) {
    return _SectionCard(
      title: 'Stock Movement History',

      child: _movements.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  product.itemType == 'stock'
                      ? 'No stock movements yet.'
                      : 'Stock is not tracked for this item.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          : Column(
              children: _movements
                  .map(
                    (movement) => _MovementRow(
                      movement: movement,
                      movementName: _movementName(movement.type),
                      date: _date(movement.occurredAt),
                      quantity: _quantity(movement.quantityDelta.abs()),
                      unitCode: movement.unitCode ?? product.unitCode ?? '',
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _EditProductDialog extends StatefulWidget {
  final ClientSession session;

  final InventoryProductDetail product;

  const _EditProductDialog({required this.session, required this.product});

  @override
  State<_EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends State<_EditProductDialog> {
  final InventoryService _service = InventoryService();

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;

  late final TextEditingController _descriptionController;

  late final TextEditingController _categoryController;

  late final TextEditingController _brandController;

  late final TextEditingController _skuController;

  late final TextEditingController _barcodeController;

  late final TextEditingController _partNumberController;

  late final TextEditingController _costController;

  late final TextEditingController _sellingController;

  late final TextEditingController _listController;

  late final TextEditingController _taxController;

  late final TextEditingController _reorderController;

  bool _saving = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    final product = widget.product;

    _nameController = TextEditingController(text: product.productName);

    _descriptionController = TextEditingController(
      text: product.description ?? '',
    );

    _categoryController = TextEditingController(
      text: product.categoryName ?? '',
    );

    _brandController = TextEditingController(text: product.brandName ?? '');

    _skuController = TextEditingController(text: product.sku);

    _barcodeController = TextEditingController(text: product.barcode ?? '');

    _partNumberController = TextEditingController(
      text: product.partNumber ?? '',
    );

    _costController = TextEditingController(text: product.costPrice.toString());

    _sellingController = TextEditingController(
      text: product.sellingPrice.toString(),
    );

    _listController = TextEditingController(
      text: product.listPrice?.toString() ?? '',
    );

    _taxController = TextEditingController(text: product.taxRate.toString());

    _reorderController = TextEditingController(
      text: product.reorderLevel.toString(),
    );
  }

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required.';
    }

    return null;
  }

  String? _numberValidator(
    String? value,
    String label, {
    bool optional = false,
  }) {
    final text = value?.trim() ?? '';

    if (text.isEmpty && optional) {
      return null;
    }

    if (text.isEmpty) {
      return '$label is required.';
    }

    final number = double.tryParse(text);

    if (number == null) {
      return 'Enter a valid number.';
    }

    if (number < 0) {
      return '$label cannot be negative.';
    }

    return null;
  }

  double _number(TextEditingController controller) {
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  double? _optionalNumber(TextEditingController controller) {
    final value = controller.text.trim();

    if (value.isEmpty) {
      return null;
    }

    return double.tryParse(value);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final tax = _number(_taxController);

    if (tax > 100) {
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
      final sku = _skuController.text.trim();
      final available = await _service.skuAvailable(
        tenantId: widget.session.business.id,
        sku: sku,
        variantId: widget.product.variantId,
      );
      if (!available) {
        throw Exception('SKU already exists. Choose a unique SKU.');
      }

      await _service.updateProduct(
        tenantId: widget.session.business.id,
        variantId: widget.product.variantId,
        name: _nameController.text,
        description: _descriptionController.text,
        categoryName: _categoryController.text,
        brandName: _brandController.text,
        sku: _skuController.text,
        barcode: _barcodeController.text,
        partNumber: _partNumberController.text,
        costPrice: _number(_costController),
        sellingPrice: _number(_sellingController),
        listPrice: _optionalNumber(_listController),
        taxRate: tax,
        reorderLevel: _number(_reorderController),
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
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
    _descriptionController.dispose();
    _categoryController.dispose();
    _brandController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _partNumberController.dispose();
    _costController.dispose();
    _sellingController.dispose();
    _listController.dispose();
    _taxController.dispose();
    _reorderController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Product'),

      content: SizedBox(
        width: 720,

        child: SingleChildScrollView(
          child: Form(
            key: _formKey,

            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _twoFields(
                  TextFormField(
                    controller: _nameController,
                    enabled: !_saving,
                    validator: (value) => _required(value, 'Product name'),
                    decoration: const InputDecoration(
                      labelText: 'Product Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  TextFormField(
                    controller: _skuController,
                    enabled: !_saving,
                    validator: (value) => _required(value, 'SKU'),
                    decoration: const InputDecoration(
                      labelText: 'SKU',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _descriptionController,
                  enabled: !_saving,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                _twoFields(
                  TextFormField(
                    controller: _categoryController,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  TextFormField(
                    controller: _brandController,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Brand',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                _twoFields(
                  TextFormField(
                    controller: _barcodeController,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Barcode',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  TextFormField(
                    controller: _partNumberController,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Part Number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                _twoFields(
                  TextFormField(
                    controller: _costController,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) => _numberValidator(value, 'Cost price'),
                    decoration: const InputDecoration(
                      labelText: 'Cost Price',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  TextFormField(
                    controller: _sellingController,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) =>
                        _numberValidator(value, 'Selling price'),
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
                    controller: _listController,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) =>
                        _numberValidator(value, 'List price', optional: true),
                    decoration: const InputDecoration(
                      labelText: 'MRP / List Price',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  TextFormField(
                    controller: _taxController,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) => _numberValidator(value, 'Tax rate'),
                    decoration: const InputDecoration(
                      labelText: 'Tax Rate',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _reorderController,
                  enabled: !_saving && widget.product.itemType == 'stock',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) => widget.product.itemType != 'stock'
                      ? null
                      : _numberValidator(value, 'Reorder level'),
                  decoration: InputDecoration(
                    labelText: 'Reorder Level',
                    suffixText: widget.product.unitCode ?? '',
                    border: const OutlineInputBorder(),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),

      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () {
                  Navigator.of(context).pop(false);
                },
          child: const Text('Cancel'),
        ),

        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving...' : 'Save Changes'),
        ),
      ],
    );
  }

  Widget _twoFields(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 520) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 14),
              Expanded(child: second),
            ],
          );
        }

        return Column(children: [first, const SizedBox(height: 14), second]);
      },
    );
  }
}

class _StockAdjustmentDialog extends StatefulWidget {
  final ClientSession session;

  final InventoryProductDetail product;

  const _StockAdjustmentDialog({required this.session, required this.product});

  @override
  State<_StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<_StockAdjustmentDialog> {
  final InventoryService _service = InventoryService();

  final _quantityController = TextEditingController();

  final _noteController = TextEditingController();

  String _direction = 'add';

  bool _saving = false;

  String? _error;

  Future<void> _save() async {
    final quantity = double.tryParse(_quantityController.text.trim());

    if (quantity == null || quantity <= 0) {
      setState(() {
        _error = 'Enter a quantity greater than zero.';
      });

      return;
    }

    final delta = _direction == 'add' ? quantity : -quantity;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _service.adjustStock(
        tenantId: widget.session.business.id,
        variantId: widget.product.variantId,
        quantityDelta: delta,
        note: _noteController.text,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
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
    _quantityController.dispose();
    _noteController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adjust Stock'),

      content: SizedBox(
        width: 440,

        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.product.productName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 5),

            Text(
              'Current stock: '
              '${widget.product.stockQuantity} '
              '${widget.product.unitCode ?? ''}',
            ),

            const SizedBox(height: 20),

            DropdownButtonFormField<String>(
              initialValue: _direction,
              decoration: const InputDecoration(
                labelText: 'Adjustment Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'add', child: Text('Add Stock')),
                DropdownMenuItem(value: 'remove', child: Text('Remove Stock')),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        _direction = value;
                      });
                    },
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _quantityController,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Quantity',
                suffixText: widget.product.unitCode ?? '',
                border: const OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _noteController,
              enabled: !_saving,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason / Note',
                hintText: 'Physical stock correction',
                border: OutlineInputBorder(),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),

              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ],
          ],
        ),
      ),

      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () {
                  Navigator.of(context).pop(false);
                },
          child: const Text('Cancel'),
        ),

        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Apply Adjustment'),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              ?trailing,
            ],
          ),

          const SizedBox(height: 20),

          child,
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;

  const _InfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),

          const SizedBox(height: 5),

          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _LargeValue extends StatelessWidget {
  final String label;
  final String value;

  const _LargeValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),

          const SizedBox(height: 6),

          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  final StockMovement movement;

  final String movementName;
  final String date;
  final String quantity;
  final String unitCode;

  const _MovementRow({
    required this.movement,
    required this.movementName,
    required this.date,
    required this.quantity,
    required this.unitCode,
  });

  @override
  Widget build(BuildContext context) {
    final incoming = movement.quantityDelta > 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),

      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: incoming ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              incoming ? Icons.arrow_downward : Icons.arrow_upward,
              color: incoming ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movementName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),

                const SizedBox(height: 3),

                Text(
                  [
                        movement.locationName,
                        if (movement.balanceBefore != null && movement.balanceAfter != null)
                          'Balance ${movement.balanceBefore!.toStringAsFixed(movement.balanceBefore! % 1 == 0 ? 0 : 3)} → ${movement.balanceAfter!.toStringAsFixed(movement.balanceAfter! % 1 == 0 ? 0 : 3)}',
                        movement.note,
                        movement.referenceNumber,
                      ]
                      .where((value) => value != null && value.isNotEmpty)
                      .join(' • '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${incoming ? '+' : '-'}'
                '$quantity $unitCode',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: incoming ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                date,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
