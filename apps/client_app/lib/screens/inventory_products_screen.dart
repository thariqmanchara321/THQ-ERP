import 'dart:async';

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
  Timer? _searchDebounce;
  Map<String, String> _productSearchIndex = const {};
  int _lowStockCount = 0;
  int _outOfStockCount = 0;
  double _inventoryValue = 0;
  double _stockUnits = 0;

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
    _productsFuture = _service
        .getProducts(
          tenantId: widget.session.business.id,
          locationId: LocationScopeService.currentForRead(widget.session),
        )
        .then((products) {
          _rebuildProductCaches(products);
          return products;
        });
  }

  void _rebuildProductCaches(List<InventoryProduct> products) {
    final searchIndex = <String, String>{};
    var low = 0;
    var out = 0;
    var value = 0.0;
    var units = 0.0;

    for (final product in products) {
      searchIndex[product.variantId] = [
        product.productName,
        product.sku,
        product.barcode ?? '',
        product.partNumber ?? '',
        product.brandName ?? '',
        product.categoryName ?? '',
      ].join('\u0001').toLowerCase();

      if (product.itemType == 'stock') {
        units += product.stockQuantity;
        value += product.costPrice * product.stockQuantity;
        if (product.stockQuantity <= 0) {
          out++;
        } else if (product.reorderLevel > 0 &&
            product.stockQuantity <= product.reorderLevel) {
          low++;
        }
      }
    }

    _productSearchIndex = Map<String, String>.unmodifiable(searchIndex);
    _lowStockCount = low;
    _outOfStockCount = out;
    _inventoryValue = value;
    _stockUnits = units;
  }

  void _searchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 140), () {
      if (mounted) setState(() => _search = value);
    });
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

    return products
        .where(
          (product) =>
              (_productSearchIndex[product.variantId] ?? '').contains(query),
        )
        .toList();
  }

  @override
  void dispose() {
    LocationScopeService.selectedLocationId.removeListener(
      _handleLocationChange,
    );
    _searchDebounce?.cancel();
    _searchController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = UiDesignScope.of(context);
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(color: profile.background),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 26,
                    decoration: BoxDecoration(
                      color: profile.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Inventory',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Products, stock, pricing and store availability',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _refresh,
                    tooltip: 'Refresh inventory',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => InventoryMovementHistoryScreen(
                          session: widget.session,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.swap_vert, size: 17),
                    label: const Text('Movement Ledger'),
                  ),
                  if (_canManage) ...[
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      onPressed: _addProduct,
                      icon: const Icon(Icons.add, size: 17),
                      label: const Text('Add Product'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 7),
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
                  final low = _lowStockCount;
                  final out = _outOfStockCount;
                  final value = _inventoryValue;
                  final units = _stockUnits;

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 820;
                      return Column(
                        children: [
                          SizedBox(
                            height: compact ? 112 : 64,
                            child: compact
                                ? Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      SizedBox(
                                        width: (constraints.maxWidth - 6) / 2,
                                        child: _inventoryMetric(
                                          'Items',
                                          '${allProducts.length}',
                                          Icons.inventory_2_outlined,
                                          profile.primary,
                                        ),
                                      ),
                                      SizedBox(
                                        width: (constraints.maxWidth - 6) / 2,
                                        child: _inventoryMetric(
                                          'Low',
                                          '$low',
                                          Icons.warning_amber_rounded,
                                          profile.primary,
                                        ),
                                      ),
                                      SizedBox(
                                        width: (constraints.maxWidth - 6) / 2,
                                        child: _inventoryMetric(
                                          'Out',
                                          '$out',
                                          Icons.remove_shopping_cart_outlined,
                                          profile.primary,
                                        ),
                                      ),
                                      SizedBox(
                                        width: (constraints.maxWidth - 6) / 2,
                                        child: _inventoryMetric(
                                          'Value',
                                          _moneyFor(
                                            widget.session.currencyCode,
                                            value,
                                          ),
                                          Icons.account_balance_wallet_outlined,
                                          profile.primary,
                                          subtitle:
                                              '${units.toStringAsFixed(0)} units',
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(
                                        child: _inventoryMetric(
                                          'Total items',
                                          '${allProducts.length}',
                                          Icons.inventory_2_outlined,
                                          profile.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _inventoryMetric(
                                          'Low stock',
                                          '$low',
                                          Icons.warning_amber_rounded,
                                          profile.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _inventoryMetric(
                                          'Out of stock',
                                          '$out',
                                          Icons.remove_shopping_cart_outlined,
                                          profile.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _inventoryMetric(
                                          'Inventory value',
                                          _moneyFor(
                                            widget.session.currencyCode,
                                            value,
                                          ),
                                          Icons.account_balance_wallet_outlined,
                                          profile.primary,
                                          subtitle:
                                              '${units.toStringAsFixed(0)} units',
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 7),
                          Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    onChanged: _searchChanged,
                                    decoration: InputDecoration(
                                      hintText:
                                          'Search product, SKU, barcode, part number or brand...',
                                      prefixIcon: const Icon(
                                        Icons.search,
                                        size: 18,
                                      ),
                                      suffixIcon: _search.isEmpty
                                          ? null
                                          : IconButton(
                                              onPressed: () {
                                                _searchDebounce?.cancel();
                                                _searchController.clear();
                                                setState(() => _search = '');
                                              },
                                              icon: const Icon(
                                                Icons.close,
                                                size: 17,
                                              ),
                                            ),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                    ),
                                  ),
                                ),
                                Container(
                                  height: 22,
                                  width: 1,
                                  color: scheme.outlineVariant,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${products.length} shown',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 5),
                              ],
                            ),
                          ),
                          const SizedBox(height: 7),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: products.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No products match your search.',
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        if (!compact)
                                          Container(
                                            height: 36,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                            color:
                                                scheme.surfaceContainerHighest,
                                            child: const Row(
                                              children: [
                                                Expanded(
                                                  flex: 4,
                                                  child: Text(
                                                    'Product',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    'SKU / Category',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    'Stock',
                                                    textAlign: TextAlign.right,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    'Cost',
                                                    textAlign: TextAlign.right,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    'Selling',
                                                    textAlign: TextAlign.right,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(width: 88),
                                                SizedBox(width: 26),
                                              ],
                                            ),
                                          ),
                                        Expanded(
                                          child: RefreshIndicator(
                                            onRefresh: _refresh,
                                            child: ListView.builder(
                                              physics:
                                                  const AlwaysScrollableScrollPhysics(),
                                              padding: EdgeInsets.zero,
                                              itemCount: products.length,
                                              itemBuilder: (context, index) {
                                                final product = products[index];
                                                return Material(
                                                  color: Colors.transparent,
                                                  child: InkWell(
                                                    onTap: () =>
                                                        _openProduct(product),
                                                    child: _ProductCard(
                                                      product: product,
                                                      currencyCode: widget
                                                          .session
                                                          .currencyCode,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inventoryMetric(
    String label,
    String value,
    IconData icon,
    Color accent, {
    String? subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
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
    if (currencyCode == 'INR') return '₹${value.toStringAsFixed(2)}';
    return '$currencyCode ${value.toStringAsFixed(2)}';
  }

  String _quantity() {
    if (product.itemType == 'service') return 'SERVICE';
    if (product.itemType != 'stock') return 'NON-STOCK';
    final decimals = product.stockQuantity % 1 == 0 ? 0 : 2;
    return '${product.stockQuantity.toStringAsFixed(decimals)} ${product.unitCode ?? ''}';
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
        final compact = constraints.maxWidth < 820;
        if (compact) {
          return Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 15,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        product.productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${product.sku}${product.categoryName?.isNotEmpty == true ? ' | ${product.categoryName}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 94,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _quantity(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: lowStock ? scheme.error : scheme.onSurface,
                        ),
                      ),
                      Text(
                        _money(product.sellingPrice),
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  width: 24,
                  child: Icon(Icons.chevron_right, size: 18),
                ),
              ],
            ),
          );
        }

        return Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        size: 15,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
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
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            [product.brandName, product.partNumber]
                                .whereType<String>()
                                .where((value) => value.isNotEmpty)
                                .join(' | '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.sku,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      product.categoryName ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _quantity(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: lowStock ? scheme.error : scheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _money(product.costPrice),
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _money(product.sellingPrice),
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(
                width: 88,
                child: lowStock
                    ? Text(
                        product.stockQuantity <= 0
                            ? 'OUT OF STOCK'
                            : 'LOW STOCK',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color: scheme.error,
                        ),
                      )
                    : Text(
                        product.itemType.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(
                width: 26,
                child: Icon(Icons.chevron_right, size: 18),
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
