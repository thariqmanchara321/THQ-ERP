import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/inventory_product.dart';
import '../services/inventory_service.dart';
import '../services/location_scope_service.dart';
import '../ui/v43_theme.dart';
import 'add_product_screen.dart';
import 'inventory_movement_history_screen.dart';
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

    LocationScopeService.selectedLocationId.addListener(_handleLocationChange);
    _loadProducts();
  }

  void _handleLocationChange() {
    if (!mounted) {
      return;
    }
    setState(_loadProducts);
  }

  void _loadProducts() {
    _productsFuture = _service.getProducts(
      tenantId: widget.session.business.id,
      locationId: LocationScopeService.currentForRead(widget.session),
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

  Future<ClientLocationAccess?> _locationForNewProduct() async {
    final selectedId = LocationScopeService.selectedLocationId.value;
    if (selectedId != null) {
      return widget.session.locations
          .where((location) => location.id == selectedId)
          .firstOrNull;
    }

    if (widget.session.locations.length == 1) {
      return widget.session.locations.first;
    }

    if (!mounted || widget.session.locations.isEmpty) {
      return null;
    }

    return showDialog<ClientLocationAccess>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Choose product store'),
        children: [
          for (final location in widget.session.locations)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, location),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.store_outlined),
                title: Text('${location.code} • ${location.name}'),
                subtitle: Text(location.type.replaceAll('_', ' ')),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addProduct() async {
    final location = await _locationForNewProduct();
    if (!mounted) {
      return;
    }
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a store before adding a product.'),
        ),
      );
      return;
    }

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddProductScreen(
          session: widget.session,
          locationId: location.id,
          locationLabel: '${location.code} • ${location.name}',
        ),
      ),
    );

    if (created == true && mounted) {
      setState(_loadProducts);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Product created for ${location.code} • ${location.name}.',
          ),
        ),
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
    LocationScopeService.selectedLocationId.removeListener(
      _handleLocationChange,
    );
    _searchController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = UiDesignScope.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: profile.background),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Inventory',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Products, stock, pricing and store availability',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _refresh,
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => InventoryMovementHistoryScreen(
                        session: widget.session,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.swap_vert),
                  label: const Text('Movement Ledger'),
                ),
                if (_canManage) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _addProduct,
                    icon: const Icon(Icons.add),
                    label: const Text('Add product'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
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
                  final allProducts =
                      snapshot.data ?? const <InventoryProduct>[];
                  if (allProducts.isEmpty) {
                    return _EmptyInventory(
                      canManage: _canManage,
                      onAdd: _addProduct,
                    );
                  }
                  final products = _filter(allProducts);
                  final low = allProducts
                      .where(
                        (p) =>
                            p.itemType == 'stock' &&
                            p.reorderLevel > 0 &&
                            p.stockQuantity <= p.reorderLevel &&
                            p.stockQuantity > 0,
                      )
                      .length;
                  final out = allProducts
                      .where(
                        (p) => p.itemType == 'stock' && p.stockQuantity <= 0,
                      )
                      .length;
                  final value = allProducts.fold<double>(
                    0,
                    (sum, p) => sum + (p.costPrice * p.stockQuantity),
                  );
                  final units = allProducts.fold<double>(
                    0,
                    (sum, p) => sum + p.stockQuantity,
                  );
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      children: [
                        LayoutBuilder(
                          builder: (context, c) {
                            final cards = [
                              (
                                'Total items',
                                '${allProducts.length}',
                                'product variants',
                                Icons.inventory_2_outlined,
                              ),
                              (
                                'Low stock',
                                '$low',
                                'needs restocking',
                                Icons.warning_amber_rounded,
                              ),
                              (
                                'Out of stock',
                                '$out',
                                'immediate attention',
                                Icons.remove_shopping_cart_outlined,
                              ),
                              (
                                'Inventory value',
                                _moneyFor(widget.session.currencyCode, value),
                                '${units.toStringAsFixed(0)} units',
                                Icons.account_balance_wallet_outlined,
                              ),
                            ];
                            final columns = c.maxWidth >= 1000
                                ? 4
                                : c.maxWidth >= 600
                                ? 2
                                : 1;
                            final gap = 10.0;
                            final width =
                                (c.maxWidth - gap * (columns - 1)) / columns;
                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: cards
                                  .map(
                                    (e) => SizedBox(
                                      width: width,
                                      child: V43Surface(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: profile.primary
                                                    .withValues(alpha: .09),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Icon(
                                                e.$4,
                                                size: 19,
                                                color: profile.primary,
                                              ),
                                            ),
                                            const SizedBox(width: 11),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    e.$1,
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    e.$2,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                  Text(
                                                    e.$3,
                                                    style: TextStyle(
                                                      fontSize: 9.5,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        V43Surface(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  onChanged: (value) =>
                                      setState(() => _search = value),
                                  decoration: InputDecoration(
                                    hintText:
                                        'Search product, SKU, barcode, part number or brand…',
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: _search.isEmpty
                                        ? null
                                        : IconButton(
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() => _search = '');
                                            },
                                            icon: const Icon(Icons.close),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.tune, size: 18),
                                label: const Text('Filters'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (products.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(
                              child: Text('No products match your search.'),
                            ),
                          )
                        else
                          V43Surface(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              children: [
                                if (MediaQuery.sizeOf(context).width >= 980)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
                                    ),
                                    child: Row(
                                      children: [
                                        const Expanded(
                                          flex: 4,
                                          child: Text(
                                            'Product',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const Expanded(
                                          flex: 2,
                                          child: Text(
                                            'SKU / Category',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const Expanded(
                                          child: Text(
                                            'Stock',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const Expanded(
                                          child: Text(
                                            'Cost',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const Expanded(
                                          child: Text(
                                            'Selling',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 70),
                                      ],
                                    ),
                                  ),
                                for (final product in products)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(
                                        profile.radius * .75,
                                      ),
                                      onTap: () => _openProduct(product),
                                      child: _ProductCard(
                                        product: product,
                                        currencyCode:
                                            widget.session.currencyCode,
                                      ),
                                    ),
                                  ),
                              ],
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
      ),
    );
  }

  String _moneyFor(String currency, double value) => currency == 'INR'
      ? '₹${value.toStringAsFixed(0)}'
      : '$currency ${value.toStringAsFixed(0)}';
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

          const SizedBox(height: 10),

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
            const SizedBox(height: 10),

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

          const SizedBox(height: 10),

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
