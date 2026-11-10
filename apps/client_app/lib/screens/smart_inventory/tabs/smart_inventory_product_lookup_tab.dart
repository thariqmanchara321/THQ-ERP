import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../../models/client_session.dart';
import '../../../services/client_smart_inventory_service.dart';
import '../../../services/location_scope_service.dart';

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

  String _filterType = 'all';

  bool get _canViewCostPrice =>
      widget.session.hasPermission('inventory.manage') ||
      widget.session.hasRole('owner');

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
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
    if (_filterType == 'all') return _results;
    return _results.where((m) {
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
        title: Text(product.productName),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (product.variantName.isNotEmpty)
                Text('Variant: ${product.variantName}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              _ModalRow(label: 'SKU', value: product.sku),
              if (product.barcode != null)
                _ModalRow(label: 'Primary Barcode', value: product.barcode!),
              if (product.partNumber != null)
                _ModalRow(label: 'Part / Mfg Code', value: product.partNumber!),
              if (product.brandName != null)
                _ModalRow(label: 'Brand', value: product.brandName!),
              if (product.categoryName != null)
                _ModalRow(label: 'Category', value: product.categoryName!),
              _ModalRow(label: 'Unit', value: '${product.unitName} (${product.unitCode})'),
              _ModalRow(label: 'Available Stock', value: '${product.stockQuantity} ${product.unitCode}'),
              _ModalRow(label: 'Selling Price', value: _formatMoney(product.sellingPrice)),
              if (_canViewCostPrice && product.costPrice != null)
                _ModalRow(label: 'Cost Price (Authorized)', value: _formatMoney(product.costPrice!)),
              if (product.identifiers.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Registered Identifiers:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: product.identifiers
                      .map((id) => Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('${id.type}: ${id.code}',
                                style: const TextStyle(fontSize: 11)),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
        actions: [
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
          // Search Input Bar
          ThqCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search by product name, SKU, barcode, QR, part or supplier code...',
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
                  Row(
                    children: [
                      const Text(
                        'Filter By: ',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('All Identifiers'),
                        selected: _filterType == 'all',
                        onSelected: (val) => setState(() => _filterType = 'all'),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Has Barcode'),
                        selected: _filterType == 'barcode',
                        onSelected: (val) => setState(() => _filterType = 'barcode'),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Has SKU'),
                        selected: _filterType == 'sku',
                        onSelected: (val) => setState(() => _filterType = 'sku'),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Has Mfg Code'),
                        selected: _filterType == 'mfg',
                        onSelected: (val) => setState(() => _filterType = 'mfg'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

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
                                Icon(Icons.search, size: 48, color: colors.onSurfaceVariant),
                                const SizedBox(height: 12),
                                const Text(
                                  'Catalog Lookup Ready',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Enter a product name, exact barcode, or SKU to search the catalog.',
                                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : filtered.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.inventory_2_outlined, size: 48, color: colors.onSurfaceVariant),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No products matching "${_searchController.text.trim()}"',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Verify the code or try searching by product name.',
                                      style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
                                    ),
                                  ],
                                ),
                              )
                            : ThqCard(
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, _) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final item = filtered[index];
                                    return ListTile(
                                      onTap: () => _showDetailModal(item),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.productName,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                                        child: Row(
                                          children: [
                                            Text('SKU: ${item.sku}', style: const TextStyle(fontSize: 12)),
                                            if (item.barcode != null) ...[
                                              const SizedBox(width: 12),
                                              Text('Barcode: ${item.barcode}', style: const TextStyle(fontSize: 12)),
                                            ],
                                            if (item.variantName.isNotEmpty) ...[
                                              const SizedBox(width: 12),
                                              Text('Variant: ${item.variantName}', style: const TextStyle(fontSize: 12)),
                                            ],
                                            const Spacer(),
                                            Text(
                                              'Stock: ${item.stockQuantity} ${item.unitCode}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: item.stockQuantity > 0 ? Colors.green : Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      trailing: const Icon(Icons.chevron_right, size: 18),
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
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
