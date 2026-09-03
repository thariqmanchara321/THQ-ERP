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
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 25,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Inventory',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Products, stock and pricing',
                        style: TextStyle(
                          fontSize: 8.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                ),
                if (_canManage) ...[
                  const SizedBox(width: 3),
                  FilledButton.icon(
                    onPressed: _addProduct,
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('Add Product'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 5),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _search = value),
              decoration: InputDecoration(
                hintText: 'Search name, SKU, barcode, part, brand...',
                prefixIcon: const Icon(Icons.search, size: 16),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                        icon: const Icon(Icons.close, size: 15),
                      ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 5),
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

                return Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: .45,
                        ),
                        child: const Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Text(
                                'Product',
                                style: TextStyle(
                                  fontSize: 8.8,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'SKU / Part',
                                style: TextStyle(
                                  fontSize: 8.8,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Price',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 8.8,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 115,
                              child: Text(
                                'Stock',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 8.8,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            SizedBox(width: 30),
                          ],
                        ),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            itemCount: products.length,
                            itemBuilder: (context, index) {
                              final product = products[index];
                              return InkWell(
                                onTap: () => _openProduct(product),
                                child: _ProductCard(
                                  product: product,
                                  currencyCode: widget.session.currencyCode,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
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
    final scheme = Theme.of(context).colorScheme;
    final lowStock =
        product.itemType == 'stock' &&
        product.reorderLevel > 0 &&
        product.stockQuantity <= product.reorderLevel;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;

        return Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: lowStock
                ? scheme.errorContainer.withValues(alpha: .08)
                : Colors.transparent,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    Container(
                      width: 27,
                      height: 27,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        size: 14,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.productName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            [
                              product.brandName ?? '',
                              product.categoryName ?? '',
                            ].where((e) => e.isNotEmpty).join(' | '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 7.4,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  compact
                      ? product.sku
                      : '${product.sku}${(product.partNumber ?? '').isEmpty ? '' : ' | ${product.partNumber}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8.2),
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _money(product.sellingPrice),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 8.8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (!compact)
                      Text(
                        'Cost ${_money(product.costPrice)}',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 7.2,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 115,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      product.itemType == 'stock'
                          ? '${product.stockQuantity.toStringAsFixed(product.stockQuantity % 1 == 0 ? 0 : 2)} ${product.unitCode ?? ''}'
                          : product.itemType.toUpperCase(),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (lowStock)
                      Text(
                        'LOW STOCK',
                        style: TextStyle(
                          fontSize: 6.8,
                          fontWeight: FontWeight.w900,
                          color: scheme.error,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(
                width: 30,
                child: Icon(Icons.chevron_right, size: 15),
              ),
            ],
          ),
        );
      },
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
