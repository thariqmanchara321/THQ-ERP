import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../../models/client_session.dart';
import '../../../services/client_smart_inventory_service.dart';
import '../../../services/location_scope_service.dart';

class SmartInventoryScanCenterTab extends StatefulWidget {
  final ClientSession session;

  const SmartInventoryScanCenterTab({super.key, required this.session});

  @override
  State<SmartInventoryScanCenterTab> createState() =>
      _SmartInventoryScanCenterTabState();
}

class _SmartInventoryScanCenterTabState
    extends State<SmartInventoryScanCenterTab> {
  final ClientSmartInventoryService _inventoryService =
      ClientSmartInventoryService.instance;

  late final SmartScannerController _scannerController;
  final TextEditingController _manualInput = TextEditingController();
  final FocusNode _manualFocus = FocusNode();

  bool _isCameraOpen = false;
  bool _isLoading = false;
  ProductIdentificationResult? _lastResult;
  ProductIdentificationMatch? _selectedCandidate;

  ScannerMode _scannerMode = ScannerMode.single;

  bool get _canViewCostPrice =>
      widget.session.hasPermission('inventory.manage') ||
      widget.session.hasRole('owner');

  @override
  void initState() {
    super.initState();
    _scannerController = SmartScannerController(
      configuration: ScannerConfiguration(
        mode: _scannerMode,
        duplicateSuppressionDuration: const Duration(milliseconds: 1200),
      ),
    );

    _scannerController.scans.listen(_onScanReceived);
    _scannerController.start();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _manualInput.dispose();
    _manualFocus.dispose();
    super.dispose();
  }

  void _onScanReceived(SmartScanResult scan) {
    _processCode(scan.rawValue, source: scan.source, format: scan.format);
  }

  Future<void> _processCode(
    String code, {
    ScannerSource source = ScannerSource.manual,
    SmartBarcodeFormat format = SmartBarcodeFormat.unknown,
  }) async {
    final clean = code.trim();
    if (clean.isEmpty) return;

    setState(() {
      _isLoading = true;
      _selectedCandidate = null;
    });

    try {
      final locationId =
          LocationScopeService.selectedLocationId.value ??
          widget.session.locations.firstOrNull?.id;

      final scanResult = SmartScanResult.valid(
        rawValue: code,
        source: source,
        format: format,
      );

      final result = await _inventoryService.identifyScan(
        scanResult,
        session: widget.session,
        locationId: locationId,
      );

      if (mounted) {
        setState(() {
          _lastResult = result;
          if (result.isExact) {
            _selectedCandidate = result.primaryMatch;
          }
          _isLoading = false;
        });

        // If continuous mode, automatically resume scanner after processing
        if (_scannerMode == ScannerMode.continuous) {
          _scannerController.resume();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastResult = ProductIdentificationResult.error(
            request: ProductIdentificationRequest(
              rawIdentifier: code,
              tenantId: widget.session.business.id,
              scannerSource: source,
            ),
            message: e.toString(),
          );
          _isLoading = false;
        });
      }
    }
  }

  void _submitManual() {
    final text = _manualInput.text;
    _manualInput.clear();
    _processCode(text, source: ScannerSource.manual);
    _manualFocus.requestFocus();
  }

  String _formatMoney(double amount) {
    final formatted = amount.toStringAsFixed(2);
    return widget.session.currencyCode == 'INR'
        ? '₹$formatted'
        : '${widget.session.currencyCode} $formatted';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final location = LocationScopeService.selectedLocation(widget.session);

    return ThqBarcodeWedgeListener(
      controller: _scannerController,
      onScan: (raw, source) => _processCode(raw, source: source),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;

          if (isDesktop) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: SingleChildScrollView(
                      child: _buildControlsPane(context, colors, location?.name),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 6,
                    child: SingleChildScrollView(
                      child: _buildResultPane(context, colors),
                    ),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildControlsPane(context, colors, location?.name),
                const SizedBox(height: 16),
                _buildResultPane(context, colors),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildControlsPane(
    BuildContext context,
    ColorScheme colors,
    String? locationName,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hardware listener status banner
        ThqCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.usb, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'USB / Bluetooth Wedge Active',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    const ThqStatusBadge(
                      status: ThqStatus.completed,
                      label: 'Listening',
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Ready to receive rapid keystroke scans from any handheld scanner. Target store: ${locationName ?? 'All Stores'}.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Mode and Camera View Toggle
        ThqCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scanner Configuration',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Single Scan'),
                        selected: _scannerMode == ScannerMode.single,
                        onSelected: (val) {
                          if (val) {
                            setState(() => _scannerMode = ScannerMode.single);
                            _scannerController.setMode(ScannerMode.single);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Continuous'),
                        selected: _scannerMode == ScannerMode.continuous,
                        onSelected: (val) {
                          if (val) {
                            setState(() => _scannerMode = ScannerMode.continuous);
                            _scannerController.setMode(ScannerMode.continuous);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ThqSecondaryButton(
                    icon: _isCameraOpen ? Icons.videocam_off : Icons.videocam,
                    label: _isCameraOpen ? 'Close Camera' : 'Camera View',
                    onPressed: () {
                      setState(() => _isCameraOpen = !_isCameraOpen);
                    },
                  ),
                ),
                if (_isCameraOpen) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 240,
                      child: ThqSmartScannerView(
                        controller: _scannerController,
                        onScan: (scan) => _onScanReceived(scan),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Manual Entry Field
        ThqCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manual Barcode / Identifier Entry',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualInput,
                        focusNode: _manualFocus,
                        onSubmitted: (_) => _submitManual(),
                        decoration: const InputDecoration(
                          hintText: 'Enter barcode, SKU, QR or part code...',
                          prefixIcon: Icon(Icons.keyboard, size: 18),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ThqPrimaryButton(
                      label: 'Identify',
                      icon: Icons.search,
                      onPressed: _submitManual,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultPane(BuildContext context, ColorScheme colors) {
    if (_isLoading) {
      return const ThqCard(
        child: SizedBox(
          height: 360,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Identifying product across catalog tiers...'),
              ],
            ),
          ),
        ),
      );
    }

    final result = _lastResult;
    if (result == null) {
      return ThqCard(
        child: SizedBox(
          height: 360,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.qr_code_scanner, size: 48, color: colors.onSurfaceVariant),
                const SizedBox(height: 16),
                const Text(
                  'Awaiting Scan Input',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Scan a physical barcode or enter a code on the left to view product details.',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Error State
    if (result.hasError) {
      return ThqCard(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Identification Error',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                result.errorMessage ?? 'An unknown error occurred during lookup.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              ThqSecondaryButton(
                label: 'Retry Scan',
                onPressed: () => _processCode(result.request.rawIdentifier),
              ),
            ],
          ),
        ),
      );
    }

    // Not Found / Offline Miss State
    if (result.isNotFound) {
      return ThqCard(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.search_off, color: Colors.orange, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    result.status == ProductIdentificationStatus.offlineMiss
                        ? 'Offline Cache Miss'
                        : 'Product Not Found',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Scanned Code: ${result.request.rawIdentifier}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                result.status == ProductIdentificationStatus.offlineMiss
                    ? 'This identifier is not cached locally. Reconnect to the network to search the live catalog.'
                    : 'No matching product, variant, barcode, or SKU was found in your business catalog.',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              ThqSecondaryButton(
                icon: Icons.refresh,
                label: 'Rescan',
                onPressed: () {
                  setState(() => _lastResult = null);
                },
              ),
            ],
          ),
        ),
      );
    }

    // Ambiguous Multiple Matches
    if (result.isAmbiguous && _selectedCandidate == null) {
      return ThqCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.call_split, color: Colors.amber, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    'Multiple Products Matched (${result.matches.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Scanned Code "${result.request.rawIdentifier}" matched multiple variants. Select the intended product below:',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: result.matches.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final candidate = result.matches[index];
                  return ListTile(
                    dense: true,
                    title: Text(candidate.productName,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      'Variant: ${candidate.variantName.isNotEmpty ? candidate.variantName : "Default"} • SKU: ${candidate.sku} • via ${candidate.matchMethod.name}',
                      style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                    ),
                    trailing: ThqPrimaryButton(
                      label: 'Select',
                      onPressed: () {
                        setState(() => _selectedCandidate = candidate);
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    // Exact Match or Selected Candidate Display
    final match = _selectedCandidate ?? result.primaryMatch;
    if (match != null) {
      return ThqCard(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.inventory_2, color: colors.primary, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          match.productName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        if (match.variantName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            match.variantName,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            ThqStatusBadge(
                              status: ThqStatus.processing,
                              label: 'Matched via ${match.matchMethod.name}',
                            ),
                            if (match.brandName != null)
                              ThqStatusBadge(
                                status: ThqStatus.neutral,
                                label: match.brandName!,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),

              // Product Attributes Grid
              _DetailRow(label: 'SKU', value: match.sku),
              if (match.barcode != null)
                _DetailRow(label: 'Barcode', value: match.barcode!),
              if (match.partNumber != null)
                _DetailRow(label: 'Part / Mfg Code', value: match.partNumber!),
              _DetailRow(label: 'Unit of Measure', value: '${match.unitName} (${match.unitCode})'),
              _DetailRow(label: 'Available Stock', value: '${match.stockQuantity} ${match.unitCode}'),
              _DetailRow(
                label: 'Selling Price',
                value: _formatMoney(match.sellingPrice),
                highlight: true,
              ),

              if (_canViewCostPrice && match.costPrice != null)
                _DetailRow(
                  label: 'Purchase Cost (Owner)',
                  value: _formatMoney(match.costPrice!),
                ),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (result.isAmbiguous)
                    ThqSecondaryButton(
                      label: 'Switch Candidate',
                      onPressed: () {
                        setState(() => _selectedCandidate = null);
                      },
                    ),
                  const SizedBox(width: 12),
                  ThqPrimaryButton(
                    icon: Icons.refresh,
                    label: 'Scan Next Product',
                    onPressed: () {
                      setState(() {
                        _lastResult = null;
                        _selectedCandidate = null;
                      });
                      _manualFocus.requestFocus();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _DetailRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
              color: highlight ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}
