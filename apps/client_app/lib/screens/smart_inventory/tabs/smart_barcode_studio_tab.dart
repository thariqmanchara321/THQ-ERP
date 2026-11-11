import 'dart:async';
import 'dart:math';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../../models/client_session.dart';
import '../../../models/inventory_product.dart';
import '../../../services/inventory_service.dart';
import '../../../services/label_printing_service.dart';
import '../../../services/location_scope_service.dart';
import '../../../services/product_identification_service.dart';

/// Interactive Barcode Studio & Label Printing Tab (Phase 8).
///
/// Enables searching catalogue items, configuring thermal rolls and A4 sheets,
/// generating GS1/internal barcodes, previewing live label designs, and printing
/// batches without altering stock balances or financial ledgers.
class SmartBarcodeStudioTab extends StatefulWidget {
  final ClientSession session;
  final List<InventoryProduct>? initialProducts;

  const SmartBarcodeStudioTab({
    super.key,
    required this.session,
    this.initialProducts,
  });

  @override
  State<SmartBarcodeStudioTab> createState() => _SmartBarcodeStudioTabState();
}

class _SmartBarcodeStudioTabState extends State<SmartBarcodeStudioTab> {
  final InventoryService _inventoryService = InventoryService();
  final ProductIdentificationService _identService =
      ProductIdentificationService();
  final LabelPrintingService _printingService = LabelPrintingService();

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  bool _isLoading = true;
  String? _errorMessage;
  List<InventoryProduct> _allProducts = [];

  // Selection & Copies state
  final Set<String> _selectedVariantIds = {};
  final Map<String, int> _copiesMap = {};
  final Map<String, String> _customBarcodes = {};

  // Filters
  String _searchQuery = '';
  String _activeFilter = 'all'; // 'all', 'missing', 'selected'

  // Template & Design State
  late LabelTemplate _currentTemplate;
  List<LabelTemplate> _templates = [];
  int _previewIndex = 0;
  bool _isCustomTemplate = false;

  // Custom template form controllers/values
  double _customWidthMm = 50.0;
  double _customHeightMm = 30.0;
  PaperMode _customPaperMode = PaperMode.thermal;
  int _customColumns = 1;
  int _customRows = 1;
  bool _customShowBusiness = true;
  bool _customShowProduct = true;
  bool _customShowPrice = true;
  bool _customShowSku = true;
  bool _customShowCodeText = true;
  bool _customShowBrand = false;
  LabelBarcodeFormat _customBarcodeFormat = LabelBarcodeFormat.code128;

  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _currentTemplate = LabelTemplate.standardThermal;
    _templates = List.from(LabelTemplate.standardPresets);
    if (widget.initialProducts != null) {
      _allProducts = widget.initialProducts!;
      _isLoading = false;
      if (_allProducts.isNotEmpty) {
        final initialSelection = _allProducts.take(3);
        for (final p in initialSelection) {
          _selectedVariantIds.add(p.variantId);
          _copiesMap[p.variantId] = 1;
        }
      }
    } else {
      _loadProducts();
      _loadDbTemplates();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final locationId =
          LocationScopeService.currentForRead(widget.session) ??
          LocationScopeService.selectedLocationId.value;

      final products = await _inventoryService.getProducts(
        tenantId: widget.session.business.id,
        locationId: locationId,
      );

      if (!mounted) return;
      setState(() {
        _allProducts = products;
        _isLoading = false;
        // Pre-select first 3 products for immediate preview convenience
        if (_selectedVariantIds.isEmpty && products.isNotEmpty) {
          final initialSelection = products.take(3);
          for (final p in initialSelection) {
            _selectedVariantIds.add(p.variantId);
            _copiesMap[p.variantId] = 1;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDbTemplates() async {
    try {
      final dbList =
          await _identService.labelTemplates(widget.session.business.id);
      if (!mounted) return;
      if (dbList.isNotEmpty) {
        final parsed = dbList.map((m) => LabelTemplate.fromMap(m)).toList();
        setState(() {
          // Merge presets and database templates, avoiding duplicates by code
          final existingCodes = _templates.map((t) => t.code).toSet();
          for (final t in parsed) {
            if (!existingCodes.contains(t.code)) {
              _templates.add(t);
            }
          }
        });
      }
    } catch (_) {
      // Non-fatal fallback to standard built-in templates
    }
  }

  // --- Filtering & Selection Helpers ---

  List<InventoryProduct> get _filteredProducts {
    var list = _allProducts;

    if (_activeFilter == 'missing') {
      list = list.where((p) => _getEffectiveBarcode(p).isEmpty).toList();
    } else if (_activeFilter == 'selected') {
      list = list.where((p) => _selectedVariantIds.contains(p.variantId)).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((p) {
        final name = p.productName.toLowerCase();
        final variant = p.variantName.toLowerCase();
        final sku = p.sku.toLowerCase();
        final barcode = _getEffectiveBarcode(p).toLowerCase();
        final category = (p.categoryName ?? '').toLowerCase();
        final brand = (p.brandName ?? '').toLowerCase();
        return name.contains(q) ||
            variant.contains(q) ||
            sku.contains(q) ||
            barcode.contains(q) ||
            category.contains(q) ||
            brand.contains(q);
      }).toList();
    }

    return list;
  }

  String _getEffectiveBarcode(InventoryProduct p) {
    if (_customBarcodes.containsKey(p.variantId)) {
      return _customBarcodes[p.variantId]!;
    }
    return (p.barcode ?? '').trim();
  }

  int _getCopies(String variantId) => _copiesMap[variantId] ?? 1;

  void _setCopies(String variantId, int count) {
    setState(() {
      _copiesMap[variantId] = max(1, count);
    });
  }

  void _toggleProductSelection(String variantId) {
    setState(() {
      if (_selectedVariantIds.contains(variantId)) {
        _selectedVariantIds.remove(variantId);
      } else {
        _selectedVariantIds.add(variantId);
        _copiesMap.putIfAbsent(variantId, () => 1);
      }
      if (_previewIndex >= _selectedVariantIds.length) {
        _previewIndex = max(0, _selectedVariantIds.length - 1);
      }
    });
  }

  void _selectAllFiltered(bool select) {
    setState(() {
      final filtered = _filteredProducts;
      if (select) {
        for (final p in filtered) {
          _selectedVariantIds.add(p.variantId);
          _copiesMap.putIfAbsent(p.variantId, () => 1);
        }
      } else {
        for (final p in filtered) {
          _selectedVariantIds.remove(p.variantId);
        }
      }
      _previewIndex = 0;
    });
  }

  void _bulkSetCopies(int copies) {
    setState(() {
      for (final id in _selectedVariantIds) {
        _copiesMap[id] = copies;
      }
    });
  }

  void _bulkMatchStock() {
    setState(() {
      for (final p in _allProducts) {
        if (_selectedVariantIds.contains(p.variantId)) {
          final stock = p.stockQuantity.toInt();
          _copiesMap[p.variantId] = max(1, stock);
        }
      }
    });
  }

  // --- Identifier Generation ---

  Future<void> _generateBarcodeForProduct(
    InventoryProduct product,
    LabelBarcodeFormat format,
  ) async {
    try {
      String generatedCode = '';
      if (format == LabelBarcodeFormat.ean13) {
        // Fallback sequence based on timestamp hash to guarantee in-store 28 prefix
        final seq = (DateTime.now().millisecondsSinceEpoch % 10000000000);
        generatedCode = BarcodeGenerator.generateInternalEan13(seq);
      } else if (format == LabelBarcodeFormat.upcA) {
        final seq = (DateTime.now().millisecondsSinceEpoch % 10000000000);
        generatedCode = BarcodeGenerator.generateInternalUpcA(seq);
      } else if (format == LabelBarcodeFormat.qrCode) {
        generatedCode = BarcodeGenerator.generateThqQrPayload(
          variantId: product.variantId,
          codeOrSequence: product.sku,
        );
      } else {
        final seq = (DateTime.now().millisecondsSinceEpoch % 1000000);
        generatedCode = BarcodeGenerator.generateCode128(
          sku: product.sku,
          sequence: seq,
        );
      }

      // Save locally immediately
      setState(() {
        _customBarcodes[product.variantId] = generatedCode;
      });

      // Persist to database if permitted
      try {
        await _identService.save(
          tenantId: widget.session.business.id,
          variantId: product.variantId,
          type: format == LabelBarcodeFormat.qrCode ? 'qr' : 'barcode',
          code: generatedCode,
          label: 'Generated via Barcode Studio',
          isPrimary: true,
          active: true,
        );
      } catch (_) {
        // Local generation succeeds even if network/offline
      }

      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(
          content: Text('Generated $format code: $generatedCode'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(
          content: Text('Generation failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _bulkGenerateMissingBarcodes() async {
    final missingSelected = _allProducts.where((p) =>
        _selectedVariantIds.contains(p.variantId) &&
        _getEffectiveBarcode(p).isEmpty).toList();

    if (missingSelected.isEmpty) {
      ThqNotify.showSnackBar(
        context,
        const SnackBar(content: Text('All selected products already have barcodes.')),
      );
      return;
    }

    var count = 0;
    for (final p in missingSelected) {
      final seq = (DateTime.now().millisecondsSinceEpoch + count) % 10000000000;
      final ean = BarcodeGenerator.generateInternalEan13(seq);
      _customBarcodes[p.variantId] = ean;
      count++;
    }

    setState(() {});
    ThqNotify.showSnackBar(
      context,
      SnackBar(
        content: Text('Generated $count in-store EAN-13 barcodes.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // --- Printing & Export Actions ---

  List<LabelPrintItem> _buildPrintItems() {
    final items = <LabelPrintItem>[];
    for (final p in _allProducts) {
      if (_selectedVariantIds.contains(p.variantId)) {
        final barcode = _getEffectiveBarcode(p);
        final copies = _getCopies(p.variantId);
        final code = barcode.isNotEmpty ? barcode : p.sku;

        items.add(
          LabelPrintItem(
            productId: p.productId,
            variantId: p.variantId,
            productName: p.productName,
            variantName: p.variantName.isNotEmpty && p.variantName != 'Standard'
                ? p.variantName
                : null,
            brandName: p.brandName,
            sku: p.sku,
            code: code,
            format: _currentTemplate.barcodeFormat,
            sellingPrice: p.sellingPrice,
            currencyCode: 'INR',
            copies: copies,
          ),
        );
      }
    }
    return items;
  }

  Future<void> _handlePrint() async {
    final items = _buildPrintItems();
    if (items.isEmpty) {
      ThqNotify.showSnackBar(
        context,
        const SnackBar(content: Text('Select at least one product to print.')),
      );
      return;
    }

    setState(() => _isPrinting = true);
    try {
      await _printingService.printBatchLabels(
        template: _currentTemplate,
        items: items,
        businessName: widget.session.business.name,
        jobName: 'THQ_Labels_${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (e) {
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(
          content: Text('Printing failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _handleExportPdf() async {
    final items = _buildPrintItems();
    if (items.isEmpty) {
      ThqNotify.showSnackBar(
        context,
        const SnackBar(content: Text('Select at least one product to export.')),
      );
      return;
    }

    setState(() => _isPrinting = true);
    try {
      final bytes = await _printingService.generatePdfBytes(
        template: _currentTemplate,
        items: items,
        businessName: widget.session.business.name,
      );

      final fileName = 'labels_${_currentTemplate.code.toLowerCase()}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (e) {
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  void _applyTemplate(LabelTemplate template) {
    setState(() {
      _currentTemplate = template;
      _isCustomTemplate = false;
      _customWidthMm = template.widthMm;
      _customHeightMm = template.heightMm;
      _customPaperMode = template.paperMode;
      _customColumns = template.columns;
      _customRows = template.rows;
      _customShowBusiness = template.showBusiness;
      _customShowProduct = template.showProduct;
      _customShowPrice = template.showPrice;
      _customShowSku = template.showSku;
      _customShowCodeText = template.showCodeText;
      _customShowBrand = template.showBrand;
      _customBarcodeFormat = template.barcodeFormat;
    });
  }

  void _updateCustomTemplate() {
    setState(() {
      _currentTemplate = LabelTemplate(
        code: 'CUSTOM_${_customWidthMm.toInt()}X${_customHeightMm.toInt()}',
        name: 'Custom (${_customWidthMm}x$_customHeightMm mm)',
        paperMode: _customPaperMode,
        widthMm: _customWidthMm,
        heightMm: _customHeightMm,
        columns: _customColumns,
        rows: _customRows,
        showBusiness: _customShowBusiness,
        showProduct: _customShowProduct,
        showPrice: _customShowPrice,
        showSku: _customShowSku,
        showCodeText: _customShowCodeText,
        showBrand: _customShowBrand,
        barcodeFormat: _customBarcodeFormat,
      );
      _isCustomTemplate = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colors.error),
            const SizedBox(height: 12),
            Text(_errorMessage!, style: TextStyle(color: colors.error)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadProducts,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Loading Products'),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 960;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Catalog & Selection Pane
            Expanded(
              flex: isWide ? 6 : 1,
              child: _buildCatalogPane(colors),
            ),

            // Divider in wide layout
            if (isWide)
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colors.outlineVariant.withValues(alpha: 0.5),
              ),

            // Right Studio & Preview Pane
            if (isWide)
              SizedBox(
                width: 440,
                child: _buildStudioPane(colors),
              ),
          ],
        );
      },
    );
  }

  // --- Catalog & Selection Pane ---

  Widget _buildCatalogPane(ColorScheme colors) {
    final filtered = _filteredProducts;
    final missingCount = _allProducts
        .where((p) => _getEffectiveBarcode(p).isEmpty)
        .length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search & Filter Bar
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search products by name, SKU, barcode, brand...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (val) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 250),
                      () => setState(() => _searchQuery = val.trim()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh Catalogue',
                onPressed: _loadProducts,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Filter Chips & Batch Operations
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: Text('All (${_allProducts.length})'),
                  selected: _activeFilter == 'all',
                  onSelected: (_) => setState(() => _activeFilter = 'all'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text('Missing Barcode ($missingCount)'),
                  selected: _activeFilter == 'missing',
                  onSelected: (_) => setState(() => _activeFilter = 'missing'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text('Selected (${_selectedVariantIds.length})'),
                  selected: _activeFilter == 'selected',
                  onSelected: (_) => setState(() => _activeFilter = 'selected'),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => _selectAllFiltered(
                    _selectedVariantIds.length < filtered.length,
                  ),
                  icon: Icon(
                    _selectedVariantIds.length >= filtered.length && filtered.isNotEmpty
                        ? Icons.deselect
                        : Icons.select_all,
                    size: 16,
                  ),
                  label: Text(
                    _selectedVariantIds.length >= filtered.length && filtered.isNotEmpty
                        ? 'Deselect All'
                        : 'Select All',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  tooltip: 'Batch Quantity Actions',
                  child: const Chip(
                    avatar: Icon(Icons.tune, size: 16),
                    label: Text('Copies & Barcodes', style: TextStyle(fontSize: 12)),
                  ),
                  onSelected: (val) {
                    if (val == '1') _bulkSetCopies(1);
                    if (val == '5') _bulkSetCopies(5);
                    if (val == 'stock') _bulkMatchStock();
                    if (val == 'gen_missing') _bulkGenerateMissingBarcodes();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: '1',
                      child: Text('Set all selected copies = 1'),
                    ),
                    const PopupMenuItem(
                      value: '5',
                      child: Text('Set all selected copies = 5'),
                    ),
                    const PopupMenuItem(
                      value: 'stock',
                      child: Text('Match copies to stock quantity'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'gen_missing',
                      child: Text('Generate EAN-13 for missing selected'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Products List Table
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No products found matching the criteria.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  )
                : Card(
                    clipBehavior: Clip.antiAlias,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final product = filtered[index];
                        final isSelected =
                            _selectedVariantIds.contains(product.variantId);
                        final barcode = _getEffectiveBarcode(product);
                        final copies = _getCopies(product.variantId);
                        final hasBarcode = barcode.isNotEmpty;

                        final isEan13Valid = hasBarcode
                            ? BarcodeValidator.isValidEan13(barcode)
                            : false;

                        return Container(
                          color: isSelected
                              ? colors.primary.withValues(alpha: 0.05)
                              : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                value: isSelected,
                                onChanged: (_) =>
                                    _toggleProductSelection(product.variantId),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      product.productName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      [
                                        'SKU: ${product.sku}',
                                        if (product.brandName != null &&
                                            product.brandName!.isNotEmpty)
                                          product.brandName!,
                                        if (product.variantName.isNotEmpty &&
                                            product.variantName != 'Standard')
                                          product.variantName,
                                      ].join(' • '),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colors.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              // Barcode display / generator button
                              Expanded(
                                flex: 3,
                                child: hasBarcode
                                    ? Row(
                                        children: [
                                          Icon(
                                            Icons.qr_code_2,
                                            size: 16,
                                            color: colors.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              barcode,
                                              style: TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: _currentTemplate
                                                                .barcodeFormat ==
                                                            LabelBarcodeFormat
                                                                .ean13 &&
                                                        !isEan13Valid
                                                    ? Colors.amber.shade900
                                                    : null,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton.icon(
                                          onPressed: () =>
                                              _generateBarcodeForProduct(
                                            product,
                                            _currentTemplate.barcodeFormat,
                                          ),
                                          icon: const Icon(
                                            Icons.auto_fix_high,
                                            size: 14,
                                          ),
                                          label: const Text(
                                            'Generate',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ),
                                      ),
                              ),
                              // Stock level
                              SizedBox(
                                width: 70,
                                child: Text(
                                  'Stock: ${product.stockQuantity.toInt()}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: product.stockQuantity <= 0
                                        ? colors.error
                                        : colors.onSurfaceVariant,
                                    fontWeight: product.stockQuantity <= 0
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              // Copies stepper
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove, size: 14),
                                    onPressed: isSelected && copies > 1
                                        ? () => _setCopies(
                                              product.variantId,
                                              copies - 1,
                                            )
                                        : null,
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: colors.outlineVariant,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '$copies',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add, size: 14),
                                    onPressed: isSelected
                                        ? () => _setCopies(
                                              product.variantId,
                                              copies + 1,
                                            )
                                        : null,
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // --- Right Studio, Template Designer & Preview Pane ---

  Widget _buildStudioPane(ColorScheme colors) {
    final selectedProducts = _allProducts
        .where((p) => _selectedVariantIds.contains(p.variantId))
        .toList();

    final totalLabels = selectedProducts.fold<int>(
      0,
      (sum, p) => sum + _getCopies(p.variantId),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Template Selector Header
          Row(
            children: [
              Expanded(
                child: Text(
                  'Label Designer',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              ThqStatusBadge(
                status: _currentTemplate.paperMode == PaperMode.thermal
                    ? ThqStatus.synced
                    : ThqStatus.draft,
                label: _currentTemplate.paperMode == PaperMode.thermal
                    ? 'Thermal Roll'
                    : 'A4 Sheet',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Template Preset Dropdown
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _isCustomTemplate ? 'CUSTOM' : _currentTemplate.code,
            decoration: InputDecoration(
              labelText: 'Label Preset',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
            items: [
              ..._templates.map(
                (t) => DropdownMenuItem(
                  value: t.code,
                  child: Text(
                    t.name,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const DropdownMenuItem(
                value: 'CUSTOM',
                child: Text(
                  'Custom Dimensions...',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ],
            onChanged: (val) {
              if (val == 'CUSTOM') {
                setState(() => _isCustomTemplate = true);
                _updateCustomTemplate();
              } else if (val != null) {
                final selected = _templates.firstWhere((t) => t.code == val);
                _applyTemplate(selected);
              }
            },
          ),
          const SizedBox(height: 12),

          // Barcode Format Selector
          DropdownButtonFormField<LabelBarcodeFormat>(
            isExpanded: true,
            initialValue: _currentTemplate.barcodeFormat,
            decoration: InputDecoration(
              labelText: 'Barcode Symbology',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(
                value: LabelBarcodeFormat.code128,
                child: Text('Code 128 (Alphanumeric • Standard)'),
              ),
              DropdownMenuItem(
                value: LabelBarcodeFormat.ean13,
                child: Text('EAN-13 (13 Digits • GS1 Check Digit)'),
              ),
              DropdownMenuItem(
                value: LabelBarcodeFormat.upcA,
                child: Text('UPC-A (12 Digits • North America)'),
              ),
              DropdownMenuItem(
                value: LabelBarcodeFormat.qrCode,
                child: Text('QR Code (2D Data Matrix)'),
              ),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _customBarcodeFormat = val;
                  _currentTemplate = _currentTemplate.copyWith(barcodeFormat: val);
                });
              }
            },
          ),
          const SizedBox(height: 12),

          // Custom Dimensions (if Custom selected)
          if (_isCustomTemplate) ...[
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _customWidthMm.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Width (mm)',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final n = double.tryParse(v);
                      if (n != null && n > 10) {
                        _customWidthMm = n;
                        _updateCustomTemplate();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: _customHeightMm.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Height (mm)',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final n = double.tryParse(v);
                      if (n != null && n > 10) {
                        _customHeightMm = n;
                        _updateCustomTemplate();
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Element Toggles Expansion / Wrap
          ExpansionTile(
            title: const Text('Printed Fields & Toggles', style: TextStyle(fontSize: 13)),
            initiallyExpanded: true,
            tilePadding: EdgeInsets.zero,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: const Text('Store Name', style: TextStyle(fontSize: 11)),
                    selected: _currentTemplate.showBusiness,
                    onSelected: (v) => setState(() {
                      _customShowBusiness = v;
                      _currentTemplate = _currentTemplate.copyWith(showBusiness: v);
                    }),
                  ),
                  FilterChip(
                    label: const Text('Product Title', style: TextStyle(fontSize: 11)),
                    selected: _currentTemplate.showProduct,
                    onSelected: (v) => setState(() {
                      _customShowProduct = v;
                      _currentTemplate = _currentTemplate.copyWith(showProduct: v);
                    }),
                  ),
                  FilterChip(
                    label: const Text('Brand / Variant', style: TextStyle(fontSize: 11)),
                    selected: _currentTemplate.showBrand,
                    onSelected: (v) => setState(() {
                      _customShowBrand = v;
                      _currentTemplate = _currentTemplate.copyWith(showBrand: v);
                    }),
                  ),
                  FilterChip(
                    label: const Text('SKU', style: TextStyle(fontSize: 11)),
                    selected: _currentTemplate.showSku,
                    onSelected: (v) => setState(() {
                      _customShowSku = v;
                      _currentTemplate = _currentTemplate.copyWith(showSku: v);
                    }),
                  ),
                  FilterChip(
                    label: const Text('Price', style: TextStyle(fontSize: 11)),
                    selected: _currentTemplate.showPrice,
                    onSelected: (v) => setState(() {
                      _customShowPrice = v;
                      _currentTemplate = _currentTemplate.copyWith(showPrice: v);
                    }),
                  ),
                  FilterChip(
                    label: const Text('Human Code', style: TextStyle(fontSize: 11)),
                    selected: _currentTemplate.showCodeText,
                    onSelected: (v) => setState(() {
                      _customShowCodeText = v;
                      _currentTemplate = _currentTemplate.copyWith(showCodeText: v);
                    }),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Live Visual Label Preview Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Live Preview',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (selectedProducts.length > 1)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: _previewIndex > 0
                          ? () => setState(() => _previewIndex--)
                          : null,
                    ),
                    Text(
                      '${_previewIndex + 1} of ${selectedProducts.length}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: _previewIndex < selectedProducts.length - 1
                          ? () => setState(() => _previewIndex++)
                          : null,
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Live Preview Visual Canvas
          _buildLiveLabelPreviewCard(
            colors,
            selectedProducts.isNotEmpty
                ? selectedProducts[_previewIndex.clamp(0, selectedProducts.length - 1)]
                : null,
          ),
          const SizedBox(height: 8),

          // Dimension info pill
          Center(
            child: Text(
              '${_currentTemplate.widthMm.toStringAsFixed(0)} × ${_currentTemplate.heightMm.toStringAsFixed(0)} mm • ${_currentTemplate.paperMode == PaperMode.thermal ? "Roll Label" : "${_currentTemplate.columns}×${_currentTemplate.rows} on A4"}',
              style: TextStyle(
                fontSize: 11,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Batch Summary Card
          ThqCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Selected Products:'),
                      Text(
                        '${selectedProducts.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Labels to Print:'),
                      Text(
                        '$totalLabels',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Text(
                    'Catalogue and printing operation only. Stock balances and ledger entries will remain untouched.',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Print & Export Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isPrinting || totalLabels == 0
                      ? null
                      : _handleExportPdf,
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('Export PDF'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isPrinting || totalLabels == 0
                      ? null
                      : _handlePrint,
                  icon: _isPrinting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.print, size: 18),
                  label: const Text('Print Labels'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Live Visual Label Canvas ---

  Widget _buildLiveLabelPreviewCard(
    ColorScheme colors,
    InventoryProduct? product,
  ) {
    if (product == null) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: const Center(
          child: Text('Select at least one product to preview label'),
        ),
      );
    }

    final barcode = _getEffectiveBarcode(product);
    final code = barcode.isNotEmpty ? barcode : product.sku;
    final price = product.sellingPrice > 0
        ? '₹${product.sellingPrice.toStringAsFixed(2)}'
        : '';

    // Calculate aspect ratio bounded
    final aspect = (_currentTemplate.widthMm / max(1.0, _currentTemplate.heightMm))
        .clamp(0.6, 2.5);

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      child: AspectRatio(
        aspectRatio: aspect,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade400, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: Store / Business
              if (_currentTemplate.showBusiness)
                Text(
                  widget.session.business.name.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

              // Product & Variant
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_currentTemplate.showBrand &&
                      (product.brandName?.isNotEmpty ?? false))
                    Text(
                      product.brandName!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                    ),
                  if (_currentTemplate.showProduct)
                    Text(
                      product.productName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),

              // Barcode / QR Rendering
              Expanded(
                child: Center(
                  child: _currentTemplate.barcodeFormat == LabelBarcodeFormat.qrCode
                      ? Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                          child: const Icon(Icons.qr_code, size: 40, color: Colors.black),
                        )
                      : CustomPaint(
                          size: const Size(double.infinity, 36),
                          painter: _BarcodePreviewPainter(code: code),
                        ),
                ),
              ),

              // Barcode Text
              if (_currentTemplate.showCodeText && code.isNotEmpty)
                Text(
                  code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 9,
                    letterSpacing: 1.2,
                  ),
                  maxLines: 1,
                ),

              // Footer: SKU & Price
              if (_currentTemplate.showSku || _currentTemplate.showPrice)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_currentTemplate.showSku)
                      Text(
                        'SKU: ${product.sku}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      const SizedBox(),
                    if (_currentTemplate.showPrice && price.isNotEmpty)
                      Text(
                        price,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A lightweight custom painter rendering realistic 1D barcode lines in UI preview.
class _BarcodePreviewPainter extends CustomPainter {
  final String code;

  const _BarcodePreviewPainter({required this.code});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    // Generate bar pattern deterministically from code string
    final seed = code.hashCode.abs();
    final random = Random(seed);
    final barCount = min(40, (size.width / 4).floor());
    if (barCount <= 0) return;

    final barWidth = size.width / (barCount * 1.5);
    var currentX = 4.0;

    for (var i = 0; i < barCount; i++) {
      final isBar = random.nextBool() || i < 2 || i > barCount - 3;
      final thick = random.nextBool();
      final width = isBar ? (thick ? barWidth * 1.8 : barWidth) : barWidth * 0.8;

      if (isBar && currentX + width < size.width - 4) {
        canvas.drawRect(
          Rect.fromLTWH(currentX, 2, width, size.height - 4),
          paint,
        );
      }
      currentX += width + (random.nextBool() ? 1.0 : 2.0);
      if (currentX >= size.width - 4) break;
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePreviewPainter oldDelegate) =>
      oldDelegate.code != code;
}

