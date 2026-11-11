import 'dart:convert';
import 'dart:typed_data';

import 'package:erp_core/erp_core.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../../models/client_session.dart';
import '../../../services/bulk_import_service.dart';
import '../../../services/location_scope_service.dart';

/// Professional desktop Smart Import tab for THQ Client application.
/// Provides a guided 7-step workflow:
/// 1. File Upload (drag-and-drop / browse for XLSX and CSV)
/// 2. Worksheet Selection (multi-sheet support for Excel)
/// 3. Column Mapping (intelligent auto-mapping with confidence indicators & manual override)
/// 4. Validation Dry-Run (mandatory fields, data types, and live catalog duplicate detection)
/// 5. Visual Pre-Import Preview (dense data table with error tooltips and status filters)
/// 6. Duplicate Resolution Strategy & Confirmation
/// 7. Batch Import Execution & Failure CSV Export
class SmartInventoryImportTab extends StatefulWidget {
  final ClientSession session;

  const SmartInventoryImportTab({super.key, required this.session});

  @override
  State<SmartInventoryImportTab> createState() =>
      _SmartInventoryImportTabState();
}

class _SmartInventoryImportTabState extends State<SmartInventoryImportTab> {
  final SmartImportEngine _engine = const SmartImportEngine();
  final SampleTemplateGenerator _templateGen = const SampleTemplateGenerator();

  // File loading state
  Uint8List? _rawFileBytes;
  String? _fileName;
  ImportFile? _importFile;
  String? _selectedSheet;
  bool _isLoadingFile = false;
  String? _fileError;

  // Mapping state
  List<ColumnMapping> _mappings = [];
  List<ProductImportField> _missingRequired = [];

  // Validation state
  bool _isValidating = false;
  int _validationProgressDone = 0;
  int _validationProgressTotal = 0;
  List<ImportRow> _validatedRows = [];
  String _previewFilter = 'all'; // 'all', 'valid', 'invalid', 'duplicate'
  String _previewSearch = '';
  final TextEditingController _searchController = TextEditingController();

  // Strategy & Execution state
  DuplicateHandlingMode _duplicateMode = DuplicateHandlingMode.skipDuplicates;
  bool _isExecuting = false;
  int _importProcessed = 0;
  int _importTotal = 0;
  ImportExecutionSummary? _executionSummary;
  String? _executionError;

  bool get _canImport =>
      widget.session.hasPermission('bulk_import.use') ||
      widget.session.hasPermission('inventory.manage') ||
      widget.session.hasRole('owner') ||
      widget.session.hasRole('admin');

  bool get _canViewCostPrice =>
      widget.session.hasPermission('inventory.manage') ||
      widget.session.hasRole('owner');

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Template Download Actions
  // ---------------------------------------------------------------------------

  Future<void> _downloadTemplate(bool isExcel) async {
    try {
      if (isExcel) {
        final bytes = _templateGen.generateXlsxBytes();
        await FileSaver.instance.saveFile(
          name: 'THQ_Product_Import_Template',
          bytes: bytes,
          fileExtension: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
      } else {
        final bytes = _templateGen.generateCsvBytes();
        await FileSaver.instance.saveFile(
          name: 'THQ_Product_Import_Template',
          bytes: bytes,
          fileExtension: 'csv',
          mimeType: MimeType.csv,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sample ${isExcel ? "Excel" : "CSV"} template saved successfully.',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save template: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // File Picking & Parsing
  // ---------------------------------------------------------------------------

  Future<void> _pickFile() async {
    const group = XTypeGroup(
      label: 'Catalogues (*.xlsx, *.csv)',
      extensions: ['xlsx', 'csv'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    await _loadBytes(bytes, file.name);
  }

  Future<void> _loadBytes(
    Uint8List bytes,
    String fileName, {
    String? sheetName,
  }) async {
    setState(() {
      _isLoadingFile = true;
      _fileError = null;
      _rawFileBytes = bytes;
      _fileName = fileName;
      _executionSummary = null;
      _executionError = null;
    });

    try {
      final file = _engine.loadFile(
        fileName: fileName,
        bytes: bytes,
        sheetName: sheetName,
      );

      if (file.hasError) {
        setState(() {
          _isLoadingFile = false;
          _fileError = file.parseError;
          _importFile = null;
          _validatedRows = [];
        });
        return;
      }

      final mappings = _engine.autoMapHeaders(file);
      final missing = _engine.columnMapper.findMissingRequiredFields(mappings);

      setState(() {
        _importFile = file;
        _selectedSheet = file.selectedWorksheet;
        _mappings = mappings;
        _missingRequired = missing;
        _isLoadingFile = false;
      });

      // Automatically run validation dry-run on newly loaded file
      await _runValidation();
    } catch (e) {
      setState(() {
        _isLoadingFile = false;
        _fileError = e.toString();
        _importFile = null;
        _validatedRows = [];
      });
    }
  }

  Future<void> _onSheetChanged(String? newSheet) async {
    if (newSheet == null ||
        newSheet == _selectedSheet ||
        _rawFileBytes == null ||
        _fileName == null) {
      return;
    }
    await _loadBytes(_rawFileBytes!, _fileName!, sheetName: newSheet);
  }

  void _resetFile() {
    setState(() {
      _rawFileBytes = null;
      _fileName = null;
      _importFile = null;
      _selectedSheet = null;
      _mappings = [];
      _missingRequired = [];
      _validatedRows = [];
      _executionSummary = null;
      _executionError = null;
      _fileError = null;
      _previewSearch = '';
      _searchController.clear();
    });
  }

  // ---------------------------------------------------------------------------
  // Column Mapping
  // ---------------------------------------------------------------------------

  void _onMappingChanged(int index, ProductImportField? field) {
    if (field == null || index < 0 || index >= _mappings.length) return;
    setState(() {
      _mappings[index] = _mappings[index].copyWith(
        destinationField: field,
        isManualOverride: true,
      );
      _missingRequired = _engine.columnMapper.findMissingRequiredFields(_mappings);
    });
    _runValidation();
  }

  void _resetAutoMap() {
    if (_importFile == null) return;
    setState(() {
      _mappings = _engine.autoMapHeaders(_importFile!);
      _missingRequired = _engine.columnMapper.findMissingRequiredFields(_mappings);
    });
    _runValidation();
  }

  // ---------------------------------------------------------------------------
  // Validation Dry Run
  // ---------------------------------------------------------------------------

  Future<void> _runValidation() async {
    if (_importFile == null) return;

    setState(() {
      _isValidating = true;
      _validationProgressDone = 0;
      _validationProgressTotal = _importFile!.totalRows;
    });

    final location = LocationScopeService.selectedLocation(widget.session);
    final config = ImportConfiguration(
      tenantId: widget.session.business.id,
      locationId: location?.id,
      deviceId: widget.session.device?.deviceId,
      canManageCostPrice: _canViewCostPrice,
      duplicateMode: _duplicateMode,
    );

    try {
      final rows = await _engine.validateAndDetectDuplicates(
        file: _importFile!,
        mappings: _mappings,
        config: config,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _validationProgressDone = done;
              _validationProgressTotal = total;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _validatedRows = rows;
          _isValidating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isValidating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Validation failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Import Execution
  // ---------------------------------------------------------------------------

  Future<void> _confirmAndExecuteImport() async {
    if (!_canImport) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You do not have permission to import products (requires inventory.manage or bulk_import.use).',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_missingRequired.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot import: missing required fields: ${_missingRequired.map((f) => f.label).join(", ")}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final validRows = _validatedRows.where((r) => r.isValid).toList();
    if (validRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid rows found to import.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final duplicateCount = _validatedRows.where((r) => r.isDuplicate).length;
    final location = LocationScopeService.selectedLocation(widget.session);

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Confirm Product Import'),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are about to import products into THQ catalog:',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              _ConfirmationRow(
                label: 'Total Rows Analyzed',
                value: '${_validatedRows.length}',
              ),
              _ConfirmationRow(
                label: 'Valid Products to Process',
                value: '${validRows.length}',
                isBold: true,
              ),
              if (duplicateCount > 0)
                _ConfirmationRow(
                  label: 'Duplicate Products',
                  value: '$duplicateCount (${_duplicateMode.label})',
                  color: Colors.amber.shade800,
                ),
              _ConfirmationRow(
                label: 'Assigned Store Scope',
                value: location?.name ?? 'All Stores',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Live stock balances will NOT be altered by this import. Products are created and catalogued safely.',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Proceed with Import'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Execute Import
    setState(() {
      _isExecuting = true;
      _importProcessed = 0;
      _importTotal = validRows.length;
      _executionSummary = null;
      _executionError = null;
    });

    final config = ImportConfiguration(
      tenantId: widget.session.business.id,
      locationId: location?.id,
      deviceId: widget.session.device?.deviceId,
      canManageCostPrice: _canViewCostPrice,
      duplicateMode: _duplicateMode,
    );

    try {
      final summary = await _engine.executeImport(
        rows: _validatedRows,
        config: config,
        onBatchCreate: (batch) async {
          final res = await BulkImportService().importProducts(
            tenantId: widget.session.business.id,
            rows: batch,
            locationId: location?.id,
            deviceId: widget.session.device?.deviceId,
          );
          return res;
        },
        onUpdateProduct: _duplicateMode == DuplicateHandlingMode.updateExisting
            ? (row) async {
                final variantId = row.existingVariantId ?? row.existingProductId;
                if (variantId != null && variantId.isNotEmpty) {
                  final sellingPrice = (row.mappedValues[ProductImportField.sellingPrice] as num?)?.toDouble() ?? 0.0;
                  final costPrice = _canViewCostPrice
                      ? ((row.mappedValues[ProductImportField.costPrice] as num?)?.toDouble() ?? 0.0)
                      : 0.0;
                  final listPrice = (row.mappedValues[ProductImportField.listPrice] as num?)?.toDouble();
                  final taxRate = (row.mappedValues[ProductImportField.taxRate] as num?)?.toDouble() ?? 0.0;
                  final reorderLevel = (row.mappedValues[ProductImportField.reorderLevel] as num?)?.toDouble() ?? 0.0;

                  await Supabase.instance.client.rpc(
                    'inventory_update_product_v628',
                    params: {
                      'p_tenant_id': widget.session.business.id,
                      'p_variant_id': variantId,
                      'p_name': row.productName,
                      'p_description': row.mappedValues[ProductImportField.description]?.toString() ?? '',
                      'p_category_name': row.mappedValues[ProductImportField.category]?.toString() ?? '',
                      'p_brand_name': row.mappedValues[ProductImportField.brand]?.toString() ?? '',
                      'p_sku': row.sku,
                      'p_barcode': row.barcode ?? '',
                      'p_part_number': row.mappedValues[ProductImportField.partNumber]?.toString() ?? '',
                      'p_cost_price': costPrice,
                      'p_selling_price': sellingPrice,
                      'p_list_price': listPrice,
                      'p_tax_rate': taxRate,
                      'p_reorder_level': reorderLevel,
                    },
                  );
                }
              }
            : null,
        onProgress: (processed, total) {
          if (mounted) {
            setState(() {
              _importProcessed = processed;
              _importTotal = total;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isExecuting = false;
          _executionSummary = summary;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExecuting = false;
          _executionError = e.toString();
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Failure CSV Export
  // ---------------------------------------------------------------------------

  Future<void> _exportFailureReport() async {
    if (_executionSummary == null || _executionSummary!.failures.isEmpty) return;
    try {
      final csv = _engine.generateErrorReport(_executionSummary!);
      final bytes = Uint8List.fromList(utf8.encode(csv));
      await FileSaver.instance.saveFile(
        name: 'THQ_Import_Failures_${DateTime.now().millisecondsSinceEpoch}',
        bytes: bytes,
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failure report CSV downloaded successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export failure report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Main Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_executionSummary != null) {
      return _buildResultsView(colors);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner & Template Download Header
          _buildHeaderBanner(colors),
          const SizedBox(height: 20),

          // File Upload & Sheet Selector Card
          _buildFileUploadCard(colors),
          const SizedBox(height: 20),

          if (_importFile != null) ...[
            // Column Mapping Section
            _buildColumnMappingSection(colors),
            const SizedBox(height: 20),

            // Pre-Import Validation & Preview Section
            _buildValidationPreviewSection(colors),
            const SizedBox(height: 20),

            // Duplicate Strategy & Execution Footer
            _buildExecutionFooter(colors),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI Sub-components
  // ---------------------------------------------------------------------------

  Widget _buildHeaderBanner(ColorScheme colors) {
    return ThqCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 800;
            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.upload_file_outlined, color: colors.primary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Smart Product Import',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Import catalogues from Excel (.xlsx) or CSV files.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _downloadTemplate(false),
                        icon: const Icon(Icons.description_outlined, size: 16),
                        label: const Text('Download CSV Template'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _downloadTemplate(true),
                        icon: const Icon(Icons.table_chart_outlined, size: 16),
                        label: const Text('Download Excel Template'),
                      ),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.upload_file_outlined, color: colors.primary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Smart Product Import',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Import product catalogues from Excel (.xlsx) or CSV files with intelligent auto-mapping, duplicate detection, and pre-import validation.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _downloadTemplate(false),
                      icon: const Icon(Icons.description_outlined, size: 16),
                      label: const Text('Download CSV Template'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _downloadTemplate(true),
                      icon: const Icon(Icons.table_chart_outlined, size: 16),
                      label: const Text('Download Excel Template'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFileUploadCard(ColorScheme colors) {
    if (_importFile != null) {
      // Loaded file summary header
      return ThqCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(
                _importFile!.fileType == ImportFileType.xlsx
                    ? Icons.table_chart
                    : Icons.text_snippet,
                color: colors.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _fileName ?? 'Selected File',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${_importFile!.totalRows} rows • ${_importFile!.headers.length} columns • ${_importFile!.fileType.name.toUpperCase()}',
                      style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (_importFile!.worksheetNames.length > 1) ...[
                const SizedBox(width: 16),
                const Text('Sheet: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: _selectedSheet,
                  underline: const SizedBox(),
                  items: _importFile!.worksheetNames.map((s) {
                    return DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)));
                  }).toList(),
                  onChanged: _onSheetChanged,
                ),
              ],
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('Change File'),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _resetFile,
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Clear File',
              ),
            ],
          ),
        ),
      );
    }

    // Unloaded file upload dropzone
    return ThqCard(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_upload_outlined, size: 32, color: colors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'Select Product Catalogue to Import',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Supports Excel (.xlsx) and CSV (.csv) with automatic character encoding and delimiter sensing.',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            if (_fileError != null) ...[
              const SizedBox(height: 12),
              Text(
                _fileError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            _isLoadingFile
                ? const CircularProgressIndicator()
                : FilledButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Browse Files'),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnMappingSection(ColorScheme colors) {
    return ThqCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: colors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Column Field Mapping',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Match supplier spreadsheet columns with THQ product fields. Product Name and SKU are required.',
                        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _resetAutoMap,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reset to Auto-Map'),
                ),
              ],
            ),
            if (_missingRequired.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Missing required column: ${_missingRequired.map((f) => f.label).join(", ")}. Please assign below.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Mapping Table
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 38,
                dataRowMinHeight: 44,
                dataRowMaxHeight: 52,
                columns: const [
                  DataColumn(label: Text('Spreadsheet Header', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Sample Data', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Confidence', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Mapped THQ Field', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: List.generate(_mappings.length, (idx) {
                  final mapping = _mappings[idx];
                  final samples = mapping.sampleValues.join(' | ');

                  return DataRow(
                    cells: [
                      DataCell(
                        Text(mapping.sourceColumn, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                      DataCell(
                        Text(
                          samples.isEmpty ? '—' : samples,
                          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DataCell(_buildConfidenceBadge(mapping.confidence, mapping.destinationField)),
                      DataCell(
                        DropdownButton<ProductImportField>(
                          value: mapping.destinationField,
                          underline: const SizedBox(),
                          isDense: true,
                          items: ProductImportField.values.map((field) {
                            return DropdownMenuItem(
                              value: field,
                              child: Text(
                                field == ProductImportField.ignore
                                    ? '— Ignore this column —'
                                    : '${field.label}${field.isRequired ? " *" : ""}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: field.isRequired ? FontWeight.bold : FontWeight.normal,
                                  color: field == ProductImportField.ignore ? colors.outline : null,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) => _onMappingChanged(idx, val),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfidenceBadge(MappingConfidence conf, ProductImportField field) {
    if (field == ProductImportField.ignore) {
      return const ThqStatusBadge(status: ThqStatus.draft, label: 'Ignored');
    }
    return switch (conf) {
      MappingConfidence.high =>
        const ThqStatusBadge(status: ThqStatus.completed, label: 'Auto (High)'),
      MappingConfidence.medium =>
        const ThqStatusBadge(status: ThqStatus.pending, label: 'Auto (Med)'),
      MappingConfidence.low =>
        const ThqStatusBadge(status: ThqStatus.draft, label: 'Manual / Low'),
      MappingConfidence.unmapped =>
        const ThqStatusBadge(status: ThqStatus.draft, label: 'Unmapped'),
    };
  }

  Widget _buildValidationPreviewSection(ColorScheme colors) {
    final total = _validatedRows.length;
    final valid = _validatedRows.where((r) => r.isValid).length;
    final invalid = _validatedRows.where((r) => r.hasErrors).length;
    final duplicates = _validatedRows.where((r) => r.isDuplicate).length;

    // Filter rows
    var filtered = _validatedRows.where((r) {
      if (_previewFilter == 'valid') return r.isValid;
      if (_previewFilter == 'invalid') return r.hasErrors;
      if (_previewFilter == 'duplicate') return r.isDuplicate;
      return true;
    }).toList();

    if (_previewSearch.trim().isNotEmpty) {
      final q = _previewSearch.toLowerCase().trim();
      filtered = filtered.where((r) {
        final cat = r.mappedValues[ProductImportField.category]?.toString().toLowerCase() ?? '';
        return r.productName.toLowerCase().contains(q) ||
            r.sku.toLowerCase().contains(q) ||
            (r.barcode?.toLowerCase().contains(q) ?? false) ||
            cat.contains(q);
      }).toList();
    }

    return ThqCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Validation & Data Preview',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Dry-run results verified against catalog schemas, bounds, and existing records.',
                      style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
                if (_isValidating)
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Checking rows ($_validationProgressDone / $_validationProgressTotal)...',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Summary Metric Chips
            Row(
              children: [
                _buildMetricCard('Total Rows', '$total', colors.onSurface, colors.surfaceContainerHighest),
                const SizedBox(width: 10),
                _buildMetricCard('Ready to Import', '$valid', Colors.green.shade800, Colors.green.shade50),
                const SizedBox(width: 10),
                _buildMetricCard('Errors Found', '$invalid', Colors.red.shade800, Colors.red.shade50),
                const SizedBox(width: 10),
                _buildMetricCard('Catalog Matches', '$duplicates', Colors.amber.shade900, Colors.amber.shade50),
              ],
            ),
            const SizedBox(height: 16),

            // Search and Status Filters
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search preview by SKU, Name, Barcode...',
                        hintStyle: const TextStyle(fontSize: 12),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _previewSearch.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _previewSearch = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (v) => setState(() => _previewSearch = v),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'valid', label: Text('Valid')),
                    ButtonSegment(value: 'invalid', label: Text('Errors')),
                    ButtonSegment(value: 'duplicate', label: Text('Duplicates')),
                  ],
                  selected: {_previewFilter},
                  onSelectionChanged: (set) => setState(() => _previewFilter = set.first),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Data Table View
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 340,
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No rows match the selected filter.',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        )
                      : SingleChildScrollView(
                          child: DataTable(
                            headingRowHeight: 36,
                            dataRowMinHeight: 38,
                            dataRowMaxHeight: 46,
                            columns: [
                              const DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                              const DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                              const DataColumn(label: Text('SKU', style: TextStyle(fontWeight: FontWeight.bold))),
                              const DataColumn(label: Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold))),
                              const DataColumn(label: Text('Barcode', style: TextStyle(fontWeight: FontWeight.bold))),
                              const DataColumn(label: Text('Selling Price', style: TextStyle(fontWeight: FontWeight.bold))),
                              if (_canViewCostPrice)
                                const DataColumn(label: Text('Cost Price', style: TextStyle(fontWeight: FontWeight.bold))),
                              const DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
                              const DataColumn(label: Text('Issues / Messages', style: TextStyle(fontWeight: FontWeight.bold))),
                            ],
                            rows: filtered.take(150).map((row) {
                              final sp = row.mappedValues[ProductImportField.sellingPrice];
                              final cp = row.mappedValues[ProductImportField.costPrice];
                              final cat = row.mappedValues[ProductImportField.category]?.toString();

                              return DataRow(
                                cells: [
                                  DataCell(Text('${row.sourceRowNumber}', style: const TextStyle(fontSize: 12))),
                                  DataCell(_buildRowStatusBadge(row)),
                                  DataCell(Text(row.sku.isNotEmpty ? row.sku : '—', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                                  DataCell(Text(row.productName.isNotEmpty ? row.productName : '—', style: const TextStyle(fontSize: 12))),
                                  DataCell(Text(row.barcode ?? '—', style: const TextStyle(fontSize: 12))),
                                  DataCell(Text(sp != null ? '₹${sp.toString()}' : '—', style: const TextStyle(fontSize: 12))),
                                  if (_canViewCostPrice)
                                    DataCell(Text(cp != null ? '₹${cp.toString()}' : '—', style: const TextStyle(fontSize: 12))),
                                  DataCell(Text(cat ?? '—', style: const TextStyle(fontSize: 12))),
                                  DataCell(_buildRowIssuesCell(row)),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                ),
              ),
            ),
            if (filtered.length > 150) ...[
              const SizedBox(height: 6),
              Text(
                'Showing first 150 of ${filtered.length} rows.',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, Color textColor, Color bgColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
            Text(label, style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }

  Widget _buildRowStatusBadge(ImportRow row) {
    if (row.hasErrors) {
      return const ThqStatusBadge(status: ThqStatus.failed, label: 'Error');
    }
    if (row.isDuplicate) {
      return const ThqStatusBadge(status: ThqStatus.pending, label: 'Duplicate');
    }
    if (row.hasWarnings) {
      return const ThqStatusBadge(status: ThqStatus.draft, label: 'Warning');
    }
    return const ThqStatusBadge(status: ThqStatus.completed, label: 'Ready');
  }

  Widget _buildRowIssuesCell(ImportRow row) {
    final issues = [...row.errors.map((e) => e.message), ...row.warnings.map((w) => w.message)];
    if (issues.isEmpty) {
      return const Text('OK', style: TextStyle(fontSize: 12, color: Colors.green));
    }
    final first = issues.first;
    return Tooltip(
      message: issues.join('\n'),
      child: Text(
        issues.length > 1 ? '$first (+${issues.length - 1} more)' : first,
        style: TextStyle(
          fontSize: 12,
          color: row.hasErrors ? Colors.red.shade800 : Colors.amber.shade900,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildExecutionFooter(ColorScheme colors) {
    final validCount = _validatedRows.where((r) => r.isValid).length;

    return ThqCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Duplicate Resolution & Import Execution',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Duplicate Strategy Radios
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: DuplicateHandlingMode.values.map((strat) {
                final isSelected = _duplicateMode == strat;
                return InkWell(
                  onTap: () {
                    setState(() => _duplicateMode = strat);
                    _runValidation();
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          size: 18,
                          color: isSelected ? colors.primary : colors.outline,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          strat.label,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            if (_executionError != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _executionError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_isExecuting) ...[
              LinearProgressIndicator(
                value: _importTotal > 0 ? _importProcessed / _importTotal : null,
              ),
              const SizedBox(height: 8),
              Text(
                'Importing products ($_importProcessed / $_importTotal processed)...',
                style: const TextStyle(fontSize: 12),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _resetFile,
                    child: const Text('Cancel / Reset'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: validCount > 0 && _missingRequired.isEmpty
                        ? _confirmAndExecuteImport
                        : null,
                    icon: const Icon(Icons.cloud_upload, size: 18),
                    label: Text('Import $validCount Products'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultsView(ColorScheme colors) {
    final summary = _executionSummary!;
    final isSuccess = summary.failedCount == 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ThqCard(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isSuccess ? Colors.green.shade50 : Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isSuccess ? Icons.check_circle : Icons.warning_amber,
                          color: isSuccess ? Colors.green.shade700 : Colors.amber.shade800,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isSuccess ? 'Import Completed Successfully' : 'Import Finished with Issues',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Processed ${summary.totalSourceRows} rows in ${(summary.duration.inMilliseconds / 1000).toStringAsFixed(2)}s',
                              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      if (summary.failures.isNotEmpty)
                        FilledButton.tonalIcon(
                          onPressed: _exportFailureReport,
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Download Failure Report (CSV)'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Results metrics
                  Row(
                    children: [
                      _buildMetricCard('Created', '${summary.createdCount}', Colors.green.shade800, Colors.green.shade50),
                      const SizedBox(width: 10),
                      _buildMetricCard('Updated', '${summary.updatedCount}', Colors.blue.shade800, Colors.blue.shade50),
                      const SizedBox(width: 10),
                      _buildMetricCard('Skipped', '${summary.skippedCount}', Colors.amber.shade900, Colors.amber.shade50),
                      const SizedBox(width: 10),
                      _buildMetricCard('Failed', '${summary.failedCount}', Colors.red.shade800, Colors.red.shade50),
                    ],
                  ),

                  if (summary.failures.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Failure Details',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 260),
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: summary.failures.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final f = summary.failures[i];
                          return ListTile(
                            dense: true,
                            leading: Text('Row ${f.sourceRowNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            title: Text(f.productName.isNotEmpty ? f.productName : (f.sku.isNotEmpty ? f.sku : 'Row ${f.sourceRowNumber}'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: Text(f.error, style: const TextStyle(fontSize: 11, color: Colors.red)),
                          );
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        onPressed: _resetFile,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Import Another File'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmationRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? color;

  const _ConfirmationRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
