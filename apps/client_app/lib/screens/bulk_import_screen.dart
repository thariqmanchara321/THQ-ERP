import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../services/bulk_import_service.dart';
import '../services/inventory_service.dart';
import '../services/location_scope_service.dart';
import 'transaction_bulk_import_panel.dart';

class BulkImportScreen extends StatefulWidget {
  final ClientSession session;
  const BulkImportScreen({super.key, required this.session});

  @override
  State<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends State<BulkImportScreen> {
  final BulkImportService _service = BulkImportService();
  final InventoryService _inventory = InventoryService();
  late final TextEditingController _csv;
  String _type = 'products';
  String? _locationId;
  bool _busy = false;
  String? _result;
  List<_ImportRow> _preview = const [];
  String? _fileName;

  static const _productHeaders = <String>[
    'name',
    'sku',
    'barcode',
    'category',
    'brand',
    'item_type',
    'part_number',
    'description',
    'cost_price',
    'selling_price',
    'list_price',
    'tax_rate',
    'reorder_level',
    'opening_stock',
    'unit',
    'hsn_sac',
    'supplier',
    'store_code',
  ];

  static const Map<String, String> _csvHeaders = {
    'customers':
        'name,contact_person,phone,email,tax_number,address_line1,address_line2,city,state,postal_code,country,credit_limit,notes',
    'suppliers':
        'name,contact_person,phone,email,tax_number,address_line1,address_line2,city,state,postal_code,country,notes',
  };

  @override
  void initState() {
    super.initState();
    final writable = LocationScopeService.writableLocations(widget.session);
    _locationId = writable.isEmpty
        ? null
        : (LocationScopeService.selectedLocationId.value ?? writable.first.id);
    if (_locationId != null && !writable.any((e) => e.id == _locationId)) {
      _locationId = writable.first.id;
    }
    _csv = TextEditingController(text: '${_csvHeaders['customers']}\n');
  }

  @override
  void dispose() {
    _csv.dispose();
    super.dispose();
  }

  Future<void> _downloadTemplate() async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Products') {
      excel.rename(defaultSheet, 'Products');
    }
    final sheet = excel['Products'];
    sheet.appendRow(_productHeaders.map((e) => TextCellValue(e)).toList());
    sheet.appendRow([
      TextCellValue('Example Product'),
      TextCellValue(''),
      TextCellValue('890000000001'),
      TextCellValue('General'),
      TextCellValue('THQ'),
      TextCellValue('stock'),
      TextCellValue('PART-001'),
      TextCellValue('Optional description'),
      DoubleCellValue(100),
      DoubleCellValue(150),
      DoubleCellValue(160),
      DoubleCellValue(18),
      DoubleCellValue(5),
      DoubleCellValue(10),
      TextCellValue('Nos'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(_selectedLocation()?.code ?? 'MAIN'),
    ]);
    final instructions = excel['Instructions'];
    instructions.appendRow([TextCellValue('THQ Product Bulk Import')]);
    instructions.appendRow([
      TextCellValue('Required'),
      TextCellValue(
        'name, selling_price (recommended), one concrete store selected in THQ',
      ),
    ]);
    instructions.appendRow([
      TextCellValue('SKU'),
      TextCellValue('Leave blank to let THQ continue its unique SKU sequence.'),
    ]);
    instructions.appendRow([
      TextCellValue('Barcode'),
      TextCellValue(
        'Optional but must be unique inside the business when supplied.',
      ),
    ]);
    instructions.appendRow([
      TextCellValue('Opening stock'),
      TextCellValue('Applied only to the store selected before import.'),
    ]);
    instructions.appendRow([
      TextCellValue('store_code'),
      TextCellValue(
        'Informational only; the selected THQ store is authoritative for safety.',
      ),
    ]);
    final raw = excel.save();
    if (raw == null) throw Exception('Could not create Excel template.');
    await FileSaver.instance.saveFile(
      name: 'THQ_Product_Import_Template_V45',
      bytes: Uint8List.fromList(raw),
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
    _message('THQ Excel template created.');
  }

  Future<void> _chooseExcel() async {
    const group = XTypeGroup(label: 'Excel', extensions: ['xlsx']);
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    setState(() {
      _busy = true;
      _result = null;
      _preview = const [];
    });
    try {
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) throw Exception('The workbook has no sheets.');
      final sheet = excel.tables.values.first;
      if (sheet.rows.isEmpty) throw Exception('The first sheet is empty.');
      final headers = sheet.rows.first
          .map((cell) => _cellText(cell?.value).trim().toLowerCase())
          .toList();
      if (!headers.contains('name')) {
        throw Exception(
          'The workbook must contain a name column. Download the THQ template first.',
        );
      }
      final rows = <Map<String, dynamic>>[];
      for (final source in sheet.rows.skip(1)) {
        final row = <String, dynamic>{};
        var hasData = false;
        for (var i = 0; i < headers.length; i++) {
          final key = headers[i];
          if (key.isEmpty) continue;
          final value = i < source.length
              ? _cellText(source[i]?.value).trim()
              : '';
          row[key] = value;
          if (value.isNotEmpty) hasData = true;
        }
        if (hasData) rows.add(row);
      }
      await _validate(rows);
      if (mounted) setState(() => _fileName = file.name);
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _cellText(CellValue? value) {
    if (value == null) return '';
    return value.toString();
  }

  Future<void> _validate(List<Map<String, dynamic>> rows) async {
    final existing = await _inventory.getProducts(
      tenantId: widget.session.business.id,
      locationId: null,
    );
    final existingSku = existing
        .map((e) => e.sku.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    final existingBarcode = existing
        .map((e) => e.barcode?.trim().toLowerCase() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet();
    final existingCategories = existing
        .map((e) => e.categoryName?.trim().toLowerCase() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet();
    final writable = LocationScopeService.writableLocations(widget.session);
    final storesByCode = {
      for (final location in writable)
        location.code.trim().toLowerCase(): location,
    };
    final selectedStore = _selectedLocation();
    final seenSku = <String>{};
    final seenBarcode = <String>{};
    final validated = <_ImportRow>[];
    for (var i = 0; i < rows.length; i++) {
      final row = Map<String, dynamic>.from(rows[i]);
      final problems = <String>[];
      final warnings = <String>[];
      final name = '${row['name'] ?? ''}'.trim();
      final sku = '${row['sku'] ?? ''}'.trim().toLowerCase();
      final barcode = '${row['barcode'] ?? ''}'.trim().toLowerCase();
      final category = '${row['category'] ?? ''}'.trim().toLowerCase();
      final storeCode = '${row['store_code'] ?? ''}'.trim().toLowerCase();
      if (name.isEmpty) problems.add('Product name is required');
      if (sku.isNotEmpty && (existingSku.contains(sku) || !seenSku.add(sku))) {
        problems.add('Duplicate SKU');
      }
      if (barcode.isNotEmpty &&
          (existingBarcode.contains(barcode) || !seenBarcode.add(barcode))) {
        problems.add('Duplicate barcode');
      }
      if (category.isNotEmpty &&
          existingCategories.isNotEmpty &&
          !existingCategories.contains(category)) {
        warnings.add('New category');
      }
      if (storeCode.isNotEmpty) {
        final workbookStore = storesByCode[storeCode];
        if (workbookStore == null) {
          problems.add('Unknown store code');
        } else if (selectedStore != null &&
            workbookStore.id != selectedStore.id) {
          problems.add(
            'Store code does not match selected store ${selectedStore.code}',
          );
        }
      }
      for (final key in [
        'cost_price',
        'selling_price',
        'list_price',
        'tax_rate',
        'reorder_level',
        'opening_stock',
      ]) {
        final value = '${row[key] ?? ''}'.trim();
        if (value.isNotEmpty && double.tryParse(value) == null) {
          problems.add('$key must be a number');
        }
      }
      validated.add(_ImportRow(i + 2, row, problems, warnings));
    }
    if (mounted) setState(() => _preview = validated);
  }

  Future<void> _importProducts() async {
    final location = _locationId;
    if (location == null) {
      _message(
        'Choose one store. Opening stock can never be imported to All Stores.',
      );
      return;
    }
    final valid = _preview
        .where((e) => e.errors.isEmpty)
        .map((e) => e.data)
        .toList();
    if (valid.isEmpty) {
      _message('There are no valid product rows to import.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _service.importProducts(
        tenantId: widget.session.business.id,
        locationId: location,
        deviceId: widget.session.device?.deviceId,
        rows: valid,
      );
      final failures = (result['errors'] as List? ?? const []);
      setState(
        () => _result =
            'Imported ${result['success_count'] ?? 0} products • Failed ${result['failed_count'] ?? 0}${failures.isEmpty ? '' : '\n${failures.take(20).join('\n')}'}',
      );
      if (failures.isNotEmpty) await _saveErrorWorkbook(failures);
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveErrorWorkbook(List failures) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Errors') {
      excel.rename(defaultSheet, 'Errors');
    }
    final sheet = excel['Errors'];
    sheet.appendRow([
      TextCellValue('Row'),
      TextCellValue('Product'),
      TextCellValue('Error'),
    ]);
    for (final raw in failures) {
      final row = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{'error': '$raw'};
      sheet.appendRow([
        IntCellValue(int.tryParse('${row['row']}') ?? 0),
        TextCellValue('${row['name'] ?? ''}'),
        TextCellValue('${row['error'] ?? ''}'),
      ]);
    }
    final bytes = excel.save();
    if (bytes != null) {
      await FileSaver.instance.saveFile(
        name: 'THQ_Product_Import_Errors',
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    }
  }

  Future<void> _saveValidationErrors() async {
    final failures = _preview
        .where((row) => row.errors.isNotEmpty)
        .map(
          (row) => <String, dynamic>{
            'row': row.rowNumber,
            'name': row.data['name'] ?? '',
            'error': row.errors.join(' • '),
          },
        )
        .toList();
    if (failures.isEmpty) {
      _message('There are no validation errors to export.');
      return;
    }
    await _saveErrorWorkbook(failures);
  }

  List<Map<String, dynamic>> _parseCsv() {
    final lines = const LineSplitter()
        .convert(_csv.text)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) return [];
    final headers = _parseLine(lines.first);
    return lines.skip(1).map((line) {
      final cells = _parseLine(line);
      final row = <String, dynamic>{};
      for (var i = 0; i < headers.length; i++) {
        row[headers[i].trim()] = i < cells.length ? cells[i].trim() : '';
      }
      return row;
    }).toList();
  }

  List<String> _parseLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (c == ',' && !quoted) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(c);
      }
    }
    result.add(buffer.toString());
    return result;
  }

  Future<void> _importParties() async {
    final rows = _parseCsv();
    if (rows.isEmpty) {
      _message('Add at least one data row.');
      return;
    }
    setState(() => _busy = true);
    try {
      final response = _type == 'customers'
          ? await _service.importCustomers(
              tenantId: widget.session.business.id,
              rows: rows,
            )
          : await _service.importSuppliers(
              tenantId: widget.session.business.id,
              rows: rows,
            );
      setState(
        () => _result =
            'Imported ${response['success_count'] ?? 0}; failed ${response['failed_count'] ?? 0}.\n${(response['errors'] as List? ?? const []).take(15).join('\n')}',
      );
    } catch (e) {
      _message(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ClientLocationAccess? _selectedLocation() {
    for (final l in LocationScopeService.writableLocations(widget.session)) {
      if (l.id == _locationId) return l;
    }
    return null;
  }

  void _message(String text) {
    if (mounted) {
      ThqNotify.showSnackBar(context, SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final writable = LocationScopeService.writableLocations(widget.session);
    return Padding(
      padding: const EdgeInsets.all(14),
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
                      'Bulk Import',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Validated imports for products, parties, sales and purchases.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'products',
                    label: Text('Products'),
                    icon: Icon(Icons.inventory_2_outlined),
                  ),
                  ButtonSegment(value: 'customers', label: Text('Customers')),
                  ButtonSegment(value: 'suppliers', label: Text('Suppliers')),
                  ButtonSegment(
                    value: 'sales',
                    label: Text('Sales'),
                    icon: Icon(Icons.receipt_long_outlined),
                  ),
                  ButtonSegment(
                    value: 'purchases',
                    label: Text('Purchases'),
                    icon: Icon(Icons.shopping_cart_outlined),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: _busy
                    ? null
                    : (v) => setState(() {
                        _type = v.first;
                        _preview = const [];
                        _result = null;
                        _csv.text = '${_csvHeaders[_type] ?? ''}\n';
                      }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_type == 'sales' || _type == 'purchases') ...[
            Expanded(
              child: TransactionBulkImportPanel(
                key: ValueKey('transaction-import-$_type'),
                session: widget.session,
                type: _type,
              ),
            ),
          ] else if (_type == 'products') ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 290,
                  child: DropdownButtonFormField<String>(
                    initialValue: _locationId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Import into store',
                    ),
                    items: writable
                        .map(
                          (l) => DropdownMenuItem(
                            value: l.id,
                            child: Text('${l.code} • ${l.name}'),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _locationId = v),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _downloadTemplate,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download THQ Excel Template'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _chooseExcel,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Choose Excel'),
                ),
                if (_fileName != null)
                  Chip(
                    label: Text(_fileName!, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _preview.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.table_view_outlined, size: 48),
                          SizedBox(height: 8),
                          Text(
                            'Choose an .xlsx file to preview it before import.',
                          ),
                          Text(
                            'Invalid rows are never posted.',
                            style: TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '${_preview.where((e) => e.errors.isEmpty).length} valid',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                '${_preview.where((e) => e.errors.isNotEmpty).length} invalid',
                              ),
                              const Spacer(),
                              Text('${_preview.length} rows'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _preview.length,
                            itemBuilder: (context, i) {
                              final r = _preview[i];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 5),
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(
                                    r.errors.isEmpty
                                        ? Icons.check_circle_outline
                                        : Icons.error_outline,
                                    color: r.errors.isEmpty
                                        ? Colors.green
                                        : Theme.of(context).colorScheme.error,
                                  ),
                                  title: Text(
                                    '${r.data['name'] ?? '(no name)'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    r.errors.isEmpty
                                        ? 'SKU: ${('${r.data['sku'] ?? ''}').isEmpty ? 'Auto' : r.data['sku']} • Barcode: ${r.data['barcode'] ?? ''}${r.warnings.isEmpty ? '' : ' • ${r.warnings.join(' • ')}'}'
                                        : r.errors.join(' • '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Text('Row ${r.rowNumber}'),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_preview.any((row) => row.errors.isNotEmpty))
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _saveValidationErrors,
                      icon: const Icon(Icons.download_for_offline_outlined),
                      label: const Text('Validation Errors'),
                    ),
                  FilledButton.icon(
                    onPressed: _busy || _preview.isEmpty
                        ? null
                        : _importProducts,
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: Text(_busy ? 'Importing…' : 'Import Valid Products'),
                  ),
                ],
              ),
            ),
          ] else ...[
            Expanded(
              child: TextField(
                controller: _csv,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'CSV data',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _busy ? null : _importParties,
                icon: const Icon(Icons.upload),
                label: Text(
                  'Import ${_type == 'customers' ? 'Customers' : 'Suppliers'}',
                ),
              ),
            ),
          ],
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(
                _result!,
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImportRow {
  final int rowNumber;
  final Map<String, dynamic> data;
  final List<String> errors;
  final List<String> warnings;
  const _ImportRow(
    this.rowNumber,
    this.data,
    this.errors, [
    this.warnings = const [],
  ]);
}
