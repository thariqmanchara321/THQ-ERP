import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../../models/client_session.dart';
import '../../../services/client_smart_inventory_service.dart';
import '../../../services/location_scope_service.dart';
import '../../product_detail_screen.dart';

/// Product Catalogue & Lookup Tab for THQ Smart Inventory (Phase 14).
///
/// Features:
/// 1. Fast, debounced multi-field catalogue search across Name, SKU, Barcode, Part #.
/// 2. Flexible identifier filters (Barcode, SKU, Mfg Code) and stock status filters.
/// 3. Compact, responsive list layout with stock health indicators.
/// 4. Detailed product breakdown modal with direct navigation to full product editor.
/// 5. Role-based cost protection ensuring restricted financial privacy.
class SmartInventoryProductLookupTab extends StatefulWidget {
  final ClientSession session;

  const SmartInventoryProductLookupTab({super.key, required this.session});

  @override
  State<SmartInventoryProductLookupTab> createState() =>
      _SmartInventoryProductLookupTabState();
}

class _SmartInventoryProductLookupTabState
    extends State<SmartInventoryProductLookupTab> {
  final ClientSmartInventoryService _service =
      ClientSmartInventoryService.instance;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  bool _isLoading = false;
  String _errorMessage = '';
  List<ProductIdentificationMatch> _results = const [];

  String _filterType = 'all'; // 'all', 'barcode', 'sku', 'mfg'
  String _stockFilter = 'all'; // 'all', 'in_stock', 'low_or_out'

  bool get _canViewCostPrice =>
      widget.session.hasPermission('inventory.view_cost') ||
      widget.session.hasPermission('inventory.manage') ||
      widget.session.hasRole('owner') ||
      widget.session.hasRole('admin');

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _executeSearch(text);
    });
  }

  Future<void> _executeSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      setState(() {
        _results = const [];
        _errorMessage = '';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final locationId = LocationScopeService.selectedLocationId.value ??
          widget.session.locations.firstOrNull?.id;

      final matches = await _service.searchCatalog(
        clean,
        session: widget.session,
        locationId: locationId,
      );

      if (mounted) {
        setState(() {
          _results = matches;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<ProductIdentificationMatch> get _filteredResults {
    var list = _results;

    if (_filterType != 'all') {
      list = list.where((m) {
        switch (_filterType) {
          case 'barcode':
            return m.barcode != null && m.barcode!.isNotEmpty;
          case 'sku':
            return m.sku.isNotEmpty;
          case 'mfg':
            return m.partNumber != null && m.partNumber!.isNotEmpty;
          default:
            return true;
        }
      }).toList();
    }

    if (_stockFilter != 'all') {
      list = list.where((m) {
        if (_stockFilter == 'in_stock') {
          return m.stockQuantity > 0;
        } else if (_stockFilter == 'low_or_out') {
          return m.stockQuantity <= 0;
        }
        return true;
      }).toList();
    }

    return list;
  }

  String _formatMoney(double amount) {
    final formatted = amount.toStringAsFixed(2);
    return widget.session.currencyCode == 'INR'
        ? '₹$formatted'
        : '${widget.session.currencyCode} $formatted';
  }

  void _showDetailModal(ProductIdentificationMatch product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          product.productName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (product.variantName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Variant: ${product.variantName}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ),
                _ModalRow(label: 'SKU', value: product.sku),
                if (product.barcode != null && product.barcode!.isNotEmpty)
                  _ModalRow(label: 'Primary Barcode', value: product.barcode!),
                if (product.partNumber != null &&
                    product.partNumber!.isNotEmpty)
                  _ModalRow(
                      label: 'Part / Mfg Code', value: product.partNumber!),
                if (product.brandName != null && product.brandName!.isNotEmpty)
                  _ModalRow(label: 'Brand', value: product.brandName!),
                if (product.categoryName != null &&
                    product.categoryName!.isNotEmpty)
                  _ModalRow(label: 'Category', value: product.categoryName!),
                _ModalRow(
                  label: 'Base Unit',
                  value: '${product.unitName} (${product.unitCode})',
                ),
                _ModalRow(
                  label: 'Available Stock',
                  value: '${product.stockQuantity} ${product.unitCode}',
                ),
                _ModalRow(
                  label: 'Selling Price',
                  value: _formatMoney(product.sellingPrice),
                ),
                if (product.costPrice != null)
                  _ModalRow(
                    label: 'Cost Price',
                    value: _canViewCostPrice
                        ? _formatMoney(product.costPrice!)
                        : '• • • • (Restricted)',
                  ),
                if (product.identifiers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Registered Identifiers:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: product.identifiers
                        .map((id) => Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                '${id.type}: ${id.code}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (product.variantId.isNotEmpty)
            ThqSecondaryButton(
              label: 'View Full Product',
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProductDetailScreen(
                      session: widget.session,
                      variantId: product.variantId,
                    ),
                  ),
                );
              },
            ),
          ThqPrimaryButton(
            label: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final filtered = _filteredResults;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search & Filter Card
          ThqCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText:
                          'Search catalogue by name, SKU, barcode, QR, or part number...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _executeSearch('');
                              },
                            )
                          : null,
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Filter By: ',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      ChoiceChip(
                        label: const Text('All Identifiers'),
                        selected: _filterType == 'all',
                        onSelected: (val) =>
                            setState(() => _filterType = 'all'),
                        visualDensity: VisualDensity.compact,
                      ),
                      ChoiceChip(
                        label: const Text('Has Barcode'),
                        selected: _filterType == 'barcode',
                        onSelected: (val) =>
                            setState(() => _filterType = 'barcode'),
                        visualDensity: VisualDensity.compact,
                      ),
                      ChoiceChip(
                        label: const Text('Has SKU'),
                        selected: _filterType == 'sku',
                        onSelected: (val) => setState(() => _filterType = 'sku'),
                        visualDensity: VisualDensity.compact,
                      ),
                      ChoiceChip(
                        label: const Text('Has Mfg Code'),
                        selected: _filterType == 'mfg',
                        onSelected: (val) => setState(() => _filterType = 'mfg'),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('All Stock'),
                        selected: _stockFilter == 'all',
                        onSelected: (val) =>
                            setState(() => _stockFilter = 'all'),
                        visualDensity: VisualDensity.compact,
                      ),
                      ChoiceChip(
                        label: const Text('In Stock'),
                        selected: _stockFilter == 'in_stock',
                        onSelected: (val) =>
                            setState(() => _stockFilter = 'in_stock'),
                        visualDensity: VisualDensity.compact,
                      ),
                      ChoiceChip(
                        label: const Text('Low / Out of Stock'),
                        selected: _stockFilter == 'low_or_out',
                        onSelected: (val) =>
                            setState(() => _stockFilter = 'low_or_out'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Search Results Counter
          if (_searchController.text.trim().isNotEmpty && !(_isLoading))
            Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 4),
              child: Text(
                'Showing ${filtered.length} of ${_results.length} search results',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),

          // Content Area
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(
                        child: Text(
                          'Search error: $_errorMessage',
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    : _searchController.text.trim().isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search,
                                    size: 48, color: colors.onSurfaceVariant),
                                const SizedBox(height: 12),
                                const Text(
                                  'Catalog Lookup Ready',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Enter a product name, exact barcode, or SKU to search the catalog.',
                                  style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : filtered.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.inventory_2_outlined,
                                        size: 48,
                                        color: colors.onSurfaceVariant),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No products matching "${_searchController.text.trim()}"',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Verify the code or try searching by product name.',
                                      style: TextStyle(
                                          color: colors.onSurfaceVariant,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              )
                            : ThqCard(
                                child: ListView.separated(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final item = filtered[index];
                                    final inStock = item.stockQuantity > 0;

                                    return ListTile(
                                      onTap: () => _showDetailModal(item),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.productName,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14),
                                            ),
                                          ),
                                          Text(
                                            _formatMoney(item.sellingPrice),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: colors.primary,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Wrap(
                                          spacing: 12,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text('SKU: ${item.sku}',
                                                style: const TextStyle(
                                                    fontSize: 12)),
                                            if (item.barcode != null &&
                                                item.barcode!.isNotEmpty)
                                              Text('Barcode: ${item.barcode}',
                                                  style: const TextStyle(
                                                      fontSize: 12)),
                                            if (item.variantName.isNotEmpty)
                                              Text(
                                                  'Variant: ${item.variantName}',
                                                  style: const TextStyle(
                                                      fontSize: 12)),
                                            if (item.brandName != null &&
                                                item.brandName!.isNotEmpty)
                                              Text('Brand: ${item.brandName}',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: colors
                                                          .onSurfaceVariant)),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: inStock
                                                    ? Colors.green.withValues(
                                                        alpha: 0.1)
                                                    : Colors.red.withValues(
                                                        alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                inStock
                                                    ? '${item.stockQuantity} ${item.unitCode}'
                                                    : 'Out of Stock',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: inStock
                                                      ? Colors.green[800]
                                                      : Colors.red[800],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      trailing: const Icon(
                                          Icons.chevron_right,
                                          size: 18),
                                    );
                                  },
                                ),
                              ),
          ),
        ],
      ),
    );
  }
}

class _ModalRow extends StatelessWidget {
  final String label;
  final String value;

  const _ModalRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
