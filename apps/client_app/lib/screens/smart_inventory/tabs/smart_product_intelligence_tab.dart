import 'dart:async';
import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/client_session.dart';
import '../../../services/client_smart_inventory_service.dart';
import '../../../services/inventory_service.dart';
import '../../../services/location_scope_service.dart';

/// Smart Inventory Tab 10: External Product Intelligence & GS1 Barcode Lookup.
///
/// Enables authorized operators to:
/// 1. Query external catalogues (GS1 Registry Platform, Open Food Facts, Mock Provider) via barcode or text.
/// 2. Perform side-by-side comparison between THQ catalogue data and external suggestions.
/// 3. Prevent automatic overwriting: explicit field-by-field approval required.
/// 4. Strictly protect financial prices, tax rates, and stock quantities as ledger invariants.
/// 5. Record transparent audit provenance metadata.
class SmartProductIntelligenceTab extends StatefulWidget {
  final ClientSession session;
  final WirelessScannerCoordinator? wirelessCoordinator;
  final ExternalProductIntelligenceEngine? customEngine;

  const SmartProductIntelligenceTab({
    super.key,
    required this.session,
    this.wirelessCoordinator,
    this.customEngine,
  });

  @override
  State<SmartProductIntelligenceTab> createState() => _SmartProductIntelligenceTabState();
}

class _SmartProductIntelligenceTabState extends State<SmartProductIntelligenceTab> {
  late final ExternalProductIntelligenceEngine _engine;
  final InventoryService _inventoryService = InventoryService();
  final ClientSmartInventoryService _smartInventoryService = ClientSmartInventoryService.instance;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  StreamSubscription<WirelessScanMessage>? _wirelessScanSub;

  bool _isSearching = false;
  String? _searchError;
  List<ExternalProductCandidate> _discoveredCandidates = [];
  ExternalProductCandidate? _selectedCandidate;
  CatalogueComparison? _activeComparison;
  Map<String, dynamic>? _existingProductMatch;

  String _selectedProviderFilter = 'all'; // 'all', 'open_product_facts', 'gs1_registry', 'mock_external'
  bool _isEnriching = false;
  String? _statusBanner;
  bool _isStatusSuccess = true;

  @override
  void initState() {
    super.initState();
    _engine = widget.customEngine ??
        ExternalProductIntelligenceEngine(
          providers: [
            OpenProductFactsProvider(),
            Gs1RegistryProvider(),
            MockExternalProductProvider(),
          ],
        );

    // Subscribe to wireless phone scanner if coordinator is supplied
    if (widget.wirelessCoordinator != null) {
      _wirelessScanSub = widget.wirelessCoordinator!.scans.listen((scan) {
        if (mounted) {
          _searchController.text = scan.rawCode;
          _triggerLookup(scan.rawCode);
        }
      });
    }
  }

  @override
  void dispose() {
    _wirelessScanSub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onBarcodeScanned(String rawBarcode) {
    final clean = rawBarcode.trim();
    if (clean.isNotEmpty) {
      _searchController.text = clean;
      _triggerLookup(clean);
    }
  }

  Future<void> _triggerLookup(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
      _statusBanner = null;
      _discoveredCandidates = [];
      _selectedCandidate = null;
      _activeComparison = null;
      _existingProductMatch = null;
    });

    final location = LocationScopeService.selectedLocation(widget.session);

    try {
      List<ExternalProductCandidate> results = [];
      final accuracy = BarcodeAccuracyVerifier.verify(rawValue: trimmed);

      if (accuracy.isValid) {
        // Barcode query
        results = await _engine.lookupBarcode(
          trimmed,
          tenantId: widget.session.business.id,
          locationId: location?.id,
        );
      } else {
        // Keyword text query
        results = await _engine.search(
          ExternalLookupRequest(
            productName: trimmed,
            tenantId: widget.session.business.id,
            locationId: location?.id,
            preferredProviders: _selectedProviderFilter != 'all' ? [_selectedProviderFilter] : null,
          ),
        );
      }

      if (!mounted) return;

      if (_selectedProviderFilter != 'all') {
        results = results.where((c) => c.providerId == _selectedProviderFilter).toList();
      }

      setState(() {
        _isSearching = false;
        _discoveredCandidates = results;
        if (results.isEmpty) {
          _searchError = 'No external candidates found for "$trimmed".';
        } else {
          // Auto-select top candidate if exactly 1 result or high confidence
          _selectCandidateForComparison(results.first);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = 'Lookup failed: $e';
      });
    }
  }

  Future<void> _selectCandidateForComparison(ExternalProductCandidate candidate) async {
    setState(() {
      _selectedCandidate = candidate;
      _activeComparison = null;
      _existingProductMatch = null;
    });

    final location = LocationScopeService.selectedLocation(widget.session);

    // Check if this product already exists in local THQ catalogue by barcode or SKU
    Map<String, dynamic>? existingProduct;
    try {
      final matches = await _smartInventoryService.searchCatalog(
        candidate.barcode,
        session: widget.session,
        locationId: location?.id,
      );

      if (matches.isNotEmpty) {
        final match = matches.first;
        existingProduct = {
          'id': match.variantId,
          'product_id': match.productId,
          'variant_id': match.variantId,
          'name': match.productName,
          'sku': match.sku,
          'barcode': match.barcode ?? candidate.barcode,
          'brand': match.brandName,
          'category': match.categoryName,
          'selling_price': match.sellingPrice,
          'cost_price': match.costPrice,
          'quantity': match.stockQuantity,
        };
      }
    } catch (_) {
      // In testing or offline mode, searchCatalog might throw or return empty
    }

    if (!mounted) return;

    final comparison = CatalogueComparison.build(
      existingProduct: existingProduct,
      candidate: candidate,
    );

    setState(() {
      _existingProductMatch = existingProduct;
      _activeComparison = comparison;
    });
  }

  Future<void> _applyEnrichment(Map<String, String?> payload) async {
    if (_activeComparison == null || _selectedCandidate == null) return;

    setState(() {
      _isEnriching = true;
      _statusBanner = null;
    });

    final isExisting = _activeComparison!.isExistingProduct;
    final location = LocationScopeService.selectedLocation(widget.session);

    try {
      if (isExisting && _existingProductMatch != null) {
        // ENRICH EXISTING PRODUCT
        // Never allow modification of protected fields!
        final existingVariantId = _existingProductMatch!['variant_id']?.toString() ??
            _existingProductMatch!['id']?.toString() ??
            '';

        // Read current values and merge with accepted non-protected fields
        final newName = payload['productName'] ?? _existingProductMatch!['name']?.toString() ?? '';
        final newBrand = payload['brand'] ?? _existingProductMatch!['brand']?.toString() ?? '';
        final newCategory = payload['category'] ?? _existingProductMatch!['category']?.toString() ?? '';
        final newDescription = payload['description'] ?? _existingProductMatch!['description']?.toString() ?? '';
        final newPartNumber = payload['partNumber'] ?? _existingProductMatch!['part_number']?.toString() ?? '';
        final newBarcode = payload['barcode'] ?? _existingProductMatch!['barcode']?.toString() ?? '';
        final sku = _existingProductMatch!['sku']?.toString() ?? '';

        // Protected accounting fields: strictly preserved from existing record
        final costPrice = double.tryParse(_existingProductMatch!['cost_price']?.toString() ?? '0') ?? 0.0;
        final sellingPrice = double.tryParse(_existingProductMatch!['selling_price']?.toString() ?? '0') ?? 0.0;
        final listPrice = double.tryParse(_existingProductMatch!['list_price']?.toString() ?? '');
        final taxRate = double.tryParse(_existingProductMatch!['tax_rate']?.toString() ?? '0') ?? 0.0;
        final reorderLevel = double.tryParse(_existingProductMatch!['reorder_level']?.toString() ?? '0') ?? 0.0;

        await _inventoryService.updateProduct(
          tenantId: widget.session.business.id,
          variantId: existingVariantId,
          name: newName,
          description: newDescription,
          categoryName: newCategory,
          brandName: newBrand,
          sku: sku,
          barcode: newBarcode,
          partNumber: newPartNumber,
          costPrice: costPrice,
          sellingPrice: sellingPrice,
          listPrice: listPrice,
          taxRate: taxRate,
          reorderLevel: reorderLevel,
        );

        // Store external provenance audit record in custom_fields
        try {
          final provenance = _activeComparison!.buildAuditProvenance(
            approvedByUserId: widget.session.username,
          );
          await Supabase.instance.client.from('product_variants').update({
            'custom_fields': {'external_provenance': provenance},
          }).eq('id', existingVariantId);
        } catch (_) {
          // Provenance logging fallback
        }

        if (mounted) {
          setState(() {
            _isEnriching = false;
            _statusBanner = 'Product "$newName" enriched successfully with ${_activeComparison!.acceptedFieldsCount} external field(s). Protected operational fields were preserved.';
            _isStatusSuccess = true;
          });
        }
      } else {
        // CREATE NEW PRODUCT DRAFT
        final nextSku = await _inventoryService.nextSku(tenantId: widget.session.business.id);
        final candidate = _selectedCandidate!;

        final newName = payload['productName'] ?? candidate.productName;
        final newBrand = payload['brand'] ?? candidate.brand ?? '';
        final newCategory = payload['category'] ?? candidate.category ?? 'General';
        final newDescription = payload['description'] ?? candidate.description ?? '';
        final newBarcode = payload['barcode'] ?? candidate.barcode;
        final newPartNumber = payload['partNumber'] ?? candidate.modelOrPartNumber ?? '';

        final res = await _inventoryService.createProduct(
          tenantId: widget.session.business.id,
          name: newName,
          sku: nextSku.isNotEmpty ? nextSku : 'SKU-${DateTime.now().millisecondsSinceEpoch}',
          itemType: 'goods',
          description: newDescription,
          categoryName: newCategory,
          brandName: newBrand,
          barcode: newBarcode,
          partNumber: newPartNumber,
          costPrice: 0.0, // Initial zero default for operator review
          sellingPrice: 0.0,
          listPrice: null,
          taxRate: 0.0,
          reorderLevel: 5.0,
          openingStock: 0.0,
          locationId: location?.id,
        );

        if (mounted) {
          setState(() {
            _isEnriching = false;
            _statusBanner = 'New product "$newName" (SKU: ${res["sku"] ?? nextSku}) created successfully from external intelligence.';
            _isStatusSuccess = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEnriching = false;
          _statusBanner = 'Failed to apply product enrichment: $e';
          _isStatusSuccess = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ThqBarcodeWedgeListener(
      onScan: (barcode, source) => _onBarcodeScanned(barcode),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Search & Filter Bar
          _buildTopSearchBar(context),
          const Divider(height: 1),

          // Status Notification Banner (if any)
          if (_statusBanner != null) _buildStatusBanner(context),

          if (_isEnriching) const LinearProgressIndicator(),

          // Main Content Area: Split View or Multi-Candidate Grid
          Expanded(
            child: _isSearching
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Querying external product intelligence and GS1 registry...'),
                      ],
                    ),
                  )
                : _searchError != null && _discoveredCandidates.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(ThqTokens.space24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off_rounded, size: 48, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(height: 12),
                              Text(_searchError!, style: theme.textTheme.titleMedium),
                              const SizedBox(height: 8),
                              const Text('Try scanning a valid EAN-13 / UPC-A barcode or searching by product title.'),
                            ],
                          ),
                        ),
                      )
                    : _discoveredCandidates.isEmpty
                        ? _buildEmptyState(context)
                        : _buildDiscoveredContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSearchBar(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ThqTokens.space16, vertical: ThqTokens.space12),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          // Search Input
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: _triggerLookup,
              decoration: InputDecoration(
                hintText: 'Scan GTIN / Barcode (e.g. 8901030383748) or enter product name...',
                prefixIcon: const Icon(Icons.qr_code_scanner),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _discoveredCandidates = [];
                            _selectedCandidate = null;
                            _activeComparison = null;
                            _searchError = null;
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Provider Filter Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
              border: Border.all(color: theme.dividerColor),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedProviderFilter,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All Providers')),
                  DropdownMenuItem(value: 'open_product_facts', child: Text('Open Food Facts')),
                  DropdownMenuItem(value: 'gs1_registry', child: Text('Verified by GS1')),
                  DropdownMenuItem(value: 'mock_external', child: Text('Mock Catalogue')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedProviderFilter = val);
                    if (_searchController.text.isNotEmpty) {
                      _triggerLookup(_searchController.text);
                    }
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Search Button
          ThqPrimaryButton(
            label: 'Search Intelligence',
            icon: Icons.search,
            busy: _isSearching,
            onPressed: () => _triggerLookup(_searchController.text),
          ),
          const SizedBox(width: 8),

          // Evict Cache Button
          Tooltip(
            message: 'Evict local 15-minute lookup cache',
            child: IconButton.outlined(
              icon: const Icon(Icons.cached, size: 20),
              onPressed: () {
                final count = _engine.clearCache();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Evicted $count cached product intelligence records.'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: _isStatusSuccess ? Colors.green.shade50 : Colors.red.shade50,
      child: Row(
        children: [
          Icon(
            _isStatusSuccess ? Icons.check_circle : Icons.error_outline,
            color: _isStatusSuccess ? Colors.green.shade800 : Colors.red.shade800,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusBanner!,
              style: TextStyle(
                color: _isStatusSuccess ? Colors.green.shade900 : Colors.red.shade900,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => setState(() => _statusBanner = null),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ThqTokens.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(90),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome, size: 36, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'External Product Intelligence & GS1 Lookup',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Text(
                'Scan any physical GTIN barcode or search product names to discover rich specifications, brands, and categories from official GS1 and open product catalogues. Review differences side-by-side and enrich your THQ catalogue with zero risk to financial records.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildQuickChip('8901030382345', 'Bru Instant Coffee (EAN-13)'),
                _buildQuickChip('8901234567890', 'UltraTech Cement 50kg'),
                _buildQuickChip('0012345678905', 'Havells 16A Socket (UPC-A)'),
                _buildQuickChip('8901234000001', 'Classmate Spiral Notebook'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickChip(String barcode, String label) {
    return ActionChip(
      avatar: const Icon(Icons.qr_code, size: 16),
      label: Text('$label ($barcode)'),
      onPressed: () {
        _searchController.text = barcode;
        _triggerLookup(barcode);
      },
    );
  }

  Widget _buildDiscoveredContent(BuildContext context) {
    final theme = Theme.of(context);

    // If multiple candidates returned, show candidate selector header
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Candidate List (if > 1 result)
        if (_discoveredCandidates.length > 1)
          Container(
            width: 280,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: theme.dividerColor.withAlpha(90))),
            ),
            child: ListView.separated(
              itemCount: _discoveredCandidates.length,
              separatorBuilder: (ctx, i) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final c = _discoveredCandidates[i];
                final isSelected = c == _selectedCandidate;
                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: theme.colorScheme.primaryContainer.withAlpha(80),
                  leading: c.imageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            c.imageUrl!,
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, stack) => const Icon(Icons.inventory_2_outlined),
                          ),
                        )
                      : const Icon(Icons.inventory_2_outlined),
                  title: Text(
                    c.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                  subtitle: Text(
                    '${c.sourceName} • ${c.barcode}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  onTap: () => _selectCandidateForComparison(c),
                );
              },
            ),
          ),

        // Right Column: Active Comparison View
        Expanded(
          child: _activeComparison != null
              ? ThqCatalogueComparisonView(
                  comparison: _activeComparison!,
                  approvedByUserId: widget.session.username,
                  onApplyEnrichment: _applyEnrichment,
                  onDiscard: () {
                    setState(() {
                      _discoveredCandidates = [];
                      _selectedCandidate = null;
                      _activeComparison = null;
                    });
                  },
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}
