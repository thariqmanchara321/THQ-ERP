import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/inventory_product.dart';
import '../services/inventory_service.dart';
import 'add_product_screen.dart';
import 'product_detail_screen.dart';

class InventoryProductsScreen extends StatefulWidget {
  final ClientSession session;

  const InventoryProductsScreen({super.key, required this.session});

  @override
  State<InventoryProductsScreen> createState() =>
      _InventoryProductsScreenState();
}

class _InventoryProductsScreenState extends State<InventoryProductsScreen> {
  final InventoryService _service = InventoryService();

  final _searchController = TextEditingController();

  late Future<List<InventoryProduct>> _productsFuture;

  String _search = '';

  bool get _canManage => widget.session.hasPermission('inventory.manage');

  @override
  void initState() {
    super.initState();

    _loadProducts();
  }

  void _loadProducts() {
    _productsFuture = _service.getProducts(
      tenantId: widget.session.business.id,
      locationId: widget.session.device?.locationId,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _loadProducts();
    });

    await _productsFuture;
  }

  Future<void> _openProduct(InventoryProduct product) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          session: widget.session,
          variantId: product.variantId,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _loadProducts();
    });
  }

  Future<void> _addProduct() async {
    final device = widget.session.device;
    if (device == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This POS terminal is not activated.')),
      );
      return;
    }
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddProductScreen(
          session: widget.session,
          locationId: device.locationId,
          locationLabel: '${device.locationCode} • ${device.locationName}',
        ),
      ),
    );

    if (created == true && mounted) {
      setState(() {
        _loadProducts();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product created successfully.')),
      );
    }
  }

  List<InventoryProduct> _filter(List<InventoryProduct> products) {
    final query = _search.trim().toLowerCase();

    if (query.isEmpty) {
      return products;
    }

    return products.where((product) {
      final values = [
        product.productName,
        product.sku,
        product.barcode ?? '',
        product.partNumber ?? '',
        product.brandName ?? '',
        product.categoryName ?? '',
      ];

      return values.any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Inventory',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    SizedBox(height: 5),

                    Text('Products, stock and pricing'),
                  ],
                ),
              ),

              if (_canManage)
                FilledButton.icon(
                  onPressed: _addProduct,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Product'),
                ),
            ],
          ),

          const SizedBox(height: 24),

          TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _search = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search name, SKU, barcode, part number, brand...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();

                        setState(() {
                          _search = '';
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),

          const SizedBox(height: 20),

          Expanded(
            child: FutureBuilder<List<InventoryProduct>>(
              future: _productsFuture,

              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _ErrorView(
                    message: snapshot.error.toString(),
                    onRetry: _refresh,
                  );
                }

                final allProducts = snapshot.data ?? [];

                final products = _filter(allProducts);

                if (allProducts.isEmpty) {
                  return _EmptyInventory(
                    canManage: _canManage,
                    onAdd: _addProduct,
                  );
                }

                if (products.isEmpty) {
                  return const Center(
                    child: Text('No products match your search.'),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,

                  child: ListView.separated(
                    itemCount: products.length,

                    separatorBuilder: (_, _) => const SizedBox(height: 10),

                    itemBuilder: (context, index) {
                      final product = products[index];

                      return InkWell(
                        borderRadius: BorderRadius.circular(16),

                        onTap: () => _openProduct(product),

                        child: _ProductCard(
                          product: product,
                          currencyCode: widget.session.currencyCode,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final InventoryProduct product;
  final String currencyCode;

  const _ProductCard({required this.product, required this.currencyCode});

  String _money(double value) {
    if (currencyCode == 'INR') {
      return '₹${value.toStringAsFixed(2)}';
    }

    return '$currencyCode ${value.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final lowStock =
        product.itemType == 'stock' &&
        product.reorderLevel > 0 &&
        product.stockQuantity <= product.reorderLevel;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: lowStock ? Colors.orange.shade200 : Colors.grey.shade200,
        ),
      ),

      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.inventory_2_outlined),
          ),

          const SizedBox(width: 16),

          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.productName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  [product.brandName, product.categoryName]
                      .where((value) => value != null && value.isNotEmpty)
                      .join(' • '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SKU', style: TextStyle(fontSize: 11)),

                Text(
                  product.sku,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),

                if (product.partNumber != null)
                  Text(
                    product.partNumber!,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),

          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cost ${_money(product.costPrice)}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),

                const SizedBox(height: 3),

                Text(
                  _money(product.sellingPrice),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  product.itemType == 'stock'
                      ? '${product.stockQuantity.toStringAsFixed(product.stockQuantity % 1 == 0 ? 0 : 2)} ${product.unitCode ?? ''}'
                      : product.itemType == 'service'
                      ? 'SERVICE'
                      : 'NON-STOCK',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),

                if (lowStock) ...[
                  const SizedBox(height: 5),

                  Text(
                    'LOW STOCK',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyInventory extends StatelessWidget {
  final bool canManage;
  final VoidCallback onAdd;

  const _EmptyInventory({required this.canManage, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 70),

          const SizedBox(height: 18),

          const Text(
            'No Products Yet',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),

          Text(
            canManage
                ? 'Create your first product and opening stock.'
                : 'No products have been created yet.',
            style: TextStyle(color: Colors.grey.shade600),
          ),

          if (canManage) ...[
            const SizedBox(height: 22),

            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add First Product'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 56),

          const SizedBox(height: 16),

          const Text(
            'Could not load inventory',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          Text(message, textAlign: TextAlign.center),

          const SizedBox(height: 20),

          OutlinedButton.icon(
            onPressed: () => onRetry(),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
