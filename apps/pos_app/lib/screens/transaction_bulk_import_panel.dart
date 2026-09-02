import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/client_session.dart';
import '../models/customer.dart';
import '../models/inventory_product.dart';
import '../models/supplier.dart';
import '../services/bulk_import_service.dart';
import '../services/customer_service.dart';
import '../services/inventory_service.dart';
import '../services/location_scope_service.dart';
import '../services/supplier_service.dart';

class TransactionBulkImportPanel extends StatefulWidget {
  final ClientSession session;
  final String type;

  const TransactionBulkImportPanel({
    super.key,
    required this.session,
    required this.type,
  }) : assert(type == 'sales' || type == 'purchases');

  @override
  State<TransactionBulkImportPanel> createState() =>
      _TransactionBulkImportPanelState();
}

class _TransactionBulkImportPanelState
    extends State<TransactionBulkImportPanel> {
  final BulkImportService _bulk = BulkImportService();
  final InventoryService _inventory = InventoryService();
  final CustomerService _customersService = CustomerService();
  final SupplierService _suppliersService = SupplierService();
  final Uuid _uuid = const Uuid();

  String? _locationId;
  bool _busy = false;
  String? _fileName;
  String? _sourceKey;
  String? _result;
  List<_TransactionImportDocument> _documents = const [];
  List<Map<String, dynamic>> _history = const [];

  bool get _isSale => widget.type == 'sales';
  String get _label => _isSale ? 'Sales' : 'Purchases';

  static const _salesHeaders = <String>[
    'document_ref',
    'sale_date',
    'due_date',
    'customer_code',
    'customer_name',
    'customer_phone',
    'sku',
    'barcode',
    'quantity',
    'unit_price',
    'tax_rate',
    'additional_charges',
    'round_off',
    'initial_payment',
    'payment_method',
    'payment_reference',
    'notes',
  ];

  static const _purchaseHeaders = <String>[
    'document_ref',
    'purchase_date',
    'due_date',
    'supplier_code',
    'supplier_name',
    'supplier_invoice_number',
    'sku',
    'barcode',
    'quantity',
    'unit_cost',
    'tax_rate',
    'additional_charges',
    'round_off',
    'initial_payment',
    'payment_method',
    'notes',
  ];

  @override
  void initState() {
    super.initState();
    final locations = LocationScopeService.writableLocations(widget.session);
    final selected = LocationScopeService.selectedLocationId.value;
    _locationId = locations.any((e) => e.id == selected)
        ? selected
        : (locations.isEmpty ? null : locations.first.id);
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant TransactionBulkImportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type) {
      setState(() {
        _documents = const [];
        _fileName = null;
        _sourceKey = null;
        _result = null;
      });
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await _bulk.transactionImportHistory(
        tenantId: widget.session.business.id,
        importType: widget.type,
        limit: 12,
      );
      if (mounted) setState(() => _history = rows);
    } catch (_) {
      // Migration 188 may not be installed yet. The import action will show the
      // authoritative backend error if the user attempts to post a file.
    }
  }

  Future<void> _downloadTemplate() async {
    final excel = Excel.createExcel();
    final sheetName = _isSale ? 'Sales' : 'Purchases';
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheetName) {
      excel.rename(defaultSheet, sheetName);
    }
    final sheet = excel[sheetName];
    final headers = _isSale ? _salesHeaders : _purchaseHeaders;
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    if (_isSale) {
      sheet.appendRow([
        TextCellValue('SALE-IMPORT-001'),
        TextCellValue(_today()),
        TextCellValue(_today()),
        TextCellValue(''),
        TextCellValue('Walk-in / customer name'),
        TextCellValue(''),
        TextCellValue('SKU-001'),
        TextCellValue(''),
        DoubleCellValue(2),
        DoubleCellValue(100),
        DoubleCellValue(18),
        DoubleCellValue(0),
        DoubleCellValue(0),
        DoubleCellValue(0),
        TextCellValue('cash'),
        TextCellValue(''),
        TextCellValue('Imported sale'),
      ]);
      sheet.appendRow([
        TextCellValue('SALE-IMPORT-001'),
        TextCellValue(_today()),
        TextCellValue(_today()),
        TextCellValue(''),
        TextCellValue('Walk-in / customer name'),
        TextCellValue(''),
        TextCellValue('SKU-002'),
        TextCellValue(''),
        DoubleCellValue(1),
        DoubleCellValue(50),
        DoubleCellValue(5),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
      ]);
    } else {
      sheet.appendRow([
        TextCellValue('PUR-IMPORT-001'),
        TextCellValue(_today()),
        TextCellValue(_today()),
        TextCellValue(''),
        TextCellValue('Supplier name'),
        TextCellValue('SUP-INV-001'),
        TextCellValue('SKU-001'),
        TextCellValue(''),
        DoubleCellValue(10),
        DoubleCellValue(75),
        DoubleCellValue(18),
        DoubleCellValue(0),
        DoubleCellValue(0),
        DoubleCellValue(0),
        TextCellValue('bank'),
        TextCellValue('Imported purchase'),
      ]);
    }
    final info = excel['Instructions'];
    info.appendRow([
      TextCellValue('THQ ERP $_label Bulk Import • v5.1.0 Build 27'),
    ]);
    info.appendRow([
      TextCellValue('Grouping'),
      TextCellValue(
        'Every row with the same document_ref becomes one transaction.',
      ),
    ]);
    info.appendRow([
      TextCellValue('Products'),
      TextCellValue(
        'Use SKU (recommended) or barcode. Serial/batch tracked products must be entered manually so trace data cannot be skipped.',
      ),
    ]);
    info.appendRow([
      TextCellValue('Parties'),
      TextCellValue(
        _isSale
            ? 'Use customer_code, exact customer_name or customer_phone. Walk-in/customer records must already exist in THQ.'
            : 'Use supplier_code or exact supplier_name. Supplier must already exist in THQ.',
      ),
    ]);
    info.appendRow([
      TextCellValue('Header values'),
      TextCellValue(
        'additional_charges, round_off, initial_payment, payment fields and notes are document-level. Put them on the first line or repeat the same values.',
      ),
    ]);
    info.appendRow([
      TextCellValue('Safety'),
      TextCellValue(
        'THQ previews and validates the entire file first. Only valid documents are sent to the normal stock/tax/payment/accounting engine.',
      ),
    ]);
    info.appendRow([TextCellValue('Dates'), TextCellValue('Use YYYY-MM-DD.')]);
    final raw = excel.save();
    if (raw == null) throw Exception('Could not create template.');
    await FileSaver.instance.saveFile(
      name: 'THQ_${_label}_Bulk_Import_Template_V490',
      bytes: Uint8List.fromList(raw),
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }

  Future<void> _chooseExcel() async {
    final locationId = _locationId;
    if (locationId == null) {
      _message('Choose a store before selecting the file.');
      return;
    }
    const group = XTypeGroup(label: 'Excel', extensions: ['xlsx']);
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    setState(() {
      _busy = true;
      _documents = const [];
      _result = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) throw Exception('Workbook has no sheets.');
      final sheet = excel.tables.values.first;
      if (sheet.rows.length < 2) throw Exception('Workbook has no data rows.');
      final headers = sheet.rows.first
          .map((cell) => _cell(cell?.value).toLowerCase())
          .toList();
      if (!headers.contains('document_ref') ||
          (!headers.contains('sku') && !headers.contains('barcode'))) {
        throw Exception(
          'Use the THQ template. document_ref and SKU/barcode columns are required.',
        );
      }
      final rows = <_SourceRow>[];
      for (var r = 1; r < sheet.rows.length; r++) {
        final source = sheet.rows[r];
        final row = <String, String>{};
        var hasData = false;
        for (var c = 0; c < headers.length; c++) {
          final key = headers[c];
          if (key.isEmpty) continue;
          final value = c < source.length ? _cell(source[c]?.value) : '';
          row[key] = value;
          if (value.isNotEmpty) hasData = true;
        }
        if (hasData) rows.add(_SourceRow(r + 1, row));
      }
      final documents = await _validate(rows, locationId);
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _fileName = file.name;
        _sourceKey = _uuid.v4();
      });
    } catch (error) {
      _message(_cleanError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<_TransactionImportDocument>> _validate(
    List<_SourceRow> rows,
    String locationId,
  ) async {
    final values = await Future.wait<dynamic>([
      _inventory.getProducts(
        tenantId: widget.session.business.id,
        locationId: locationId,
      ),
      if (_isSale)
        _customersService.getCustomers(tenantId: widget.session.business.id)
      else
        _suppliersService.getSuppliers(tenantId: widget.session.business.id),
    ]);
    final products = (values[0] as List<InventoryProduct>);
    final parties = values[1] as List;

    final bySku = <String, InventoryProduct>{};
    final byBarcode = <String, InventoryProduct>{};
    for (final product in products) {
      if (product.sku.trim().isNotEmpty) {
        bySku[product.sku.trim().toLowerCase()] = product;
      }
      final barcode = product.barcode?.trim().toLowerCase() ?? '';
      if (barcode.isNotEmpty) byBarcode[barcode] = product;
    }

    final groups = <String, List<_SourceRow>>{};
    final ungrouped = <_TransactionImportDocument>[];
    for (final row in rows) {
      final ref = _value(row.data, 'document_ref');
      if (ref.isEmpty) {
        ungrouped.add(
          _TransactionImportDocument(
            reference: 'Row ${row.rowNumber}',
            rowCount: 1,
            payload: const {},
            errors: ['Row ${row.rowNumber}: document_ref is required.'],
            total: 0,
          ),
        );
        continue;
      }
      groups.putIfAbsent(ref, () => []).add(row);
    }

    final output = <_TransactionImportDocument>[...ungrouped];
    for (final entry in groups.entries) {
      final ref = entry.key;
      final sourceRows = entry.value;
      final first = sourceRows.first;
      final errors = <String>[];
      final items = <Map<String, dynamic>>[];
      final usedVariants = <String>{};
      dynamic party;

      if (_isSale) {
        party = _resolveCustomer(
          parties.cast<Customer>(),
          code: _value(first.data, 'customer_code'),
          name: _value(first.data, 'customer_name'),
          phone: _value(first.data, 'customer_phone'),
        );
        if (party == null) {
          errors.add(
            'Customer not found. Use an existing customer code, exact name or phone.',
          );
        } else if (!(party as Customer).isActive) {
          errors.add('Customer is inactive.');
        }
      } else {
        party = _resolveSupplier(
          parties.cast<Supplier>(),
          code: _value(first.data, 'supplier_code'),
          name: _value(first.data, 'supplier_name'),
        );
        if (party == null) {
          errors.add(
            'Supplier not found. Use an existing supplier code or exact name.',
          );
        } else if (!(party as Supplier).isActive) {
          errors.add('Supplier is inactive.');
        }
        if (_value(first.data, 'supplier_invoice_number').isEmpty) {
          errors.add('Supplier invoice number is required.');
        }
      }

      final dateKey = _isSale ? 'sale_date' : 'purchase_date';
      final documentDate = _date(_value(first.data, dateKey));
      final dueDate = _date(_value(first.data, 'due_date'), allowBlank: true);
      if (documentDate == null) errors.add('$dateKey must use YYYY-MM-DD.');
      if (_value(first.data, 'due_date').isNotEmpty && dueDate == null) {
        errors.add('due_date must use YYYY-MM-DD.');
      }

      var subtotal = 0.0;
      var tax = 0.0;
      for (final row in sourceRows) {
        final sku = _value(row.data, 'sku').toLowerCase();
        final barcode = _value(row.data, 'barcode').toLowerCase();
        final product = sku.isNotEmpty ? bySku[sku] : byBarcode[barcode];
        if (product == null) {
          errors.add(
            'Row ${row.rowNumber}: product not found for SKU/barcode.',
          );
          continue;
        }
        if (product.trackingMode != 'none') {
          errors.add(
            'Row ${row.rowNumber}: ${product.productName} is ${product.trackingMode}-tracked. Use New ${_isSale ? 'Sale' : 'Purchase'} so serial/batch trace details are captured.',
          );
          continue;
        }
        if (!usedVariants.add(product.variantId)) {
          errors.add(
            'Row ${row.rowNumber}: ${product.productName} is repeated in the same document. Combine it into one line.',
          );
          continue;
        }
        final quantity = _number(_value(row.data, 'quantity'));
        if (quantity == null || quantity <= 0) {
          errors.add('Row ${row.rowNumber}: quantity must be greater than 0.');
          continue;
        }
        final priceKey = _isSale ? 'unit_price' : 'unit_cost';
        final entered = _number(_value(row.data, priceKey));
        final price =
            entered ?? (_isSale ? product.sellingPrice : product.costPrice);
        if (price < 0) {
          errors.add('Row ${row.rowNumber}: $priceKey cannot be negative.');
          continue;
        }
        final rate = _number(_value(row.data, 'tax_rate')) ?? product.taxRate;
        if (rate < 0 || rate > 100) {
          errors.add(
            'Row ${row.rowNumber}: tax_rate must be between 0 and 100.',
          );
          continue;
        }
        final line = quantity * price;
        subtotal += line;
        tax += line * rate / 100;
        items.add({
          'variant_id': product.variantId,
          'quantity': quantity,
          if (_isSale) 'unit_price': price else 'unit_cost': price,
          'tax_rate': rate,
        });
      }

      final additional = _number(_value(first.data, 'additional_charges')) ?? 0;
      final roundOff = _number(_value(first.data, 'round_off')) ?? 0;
      final initialPayment =
          _number(_value(first.data, 'initial_payment')) ?? 0;
      if (additional < 0) errors.add('Additional charges cannot be negative.');
      if (roundOff.abs() > 0.999999) {
        errors.add('Round off must be between -1.00 and 1.00.');
      }
      final total = subtotal + tax + additional + roundOff;
      if (initialPayment < 0 || initialPayment > total + 0.005) {
        errors.add('Initial payment must be between 0 and the document total.');
      }
      if (items.isEmpty) errors.add('No valid product lines were found.');

      final partyId = party is Customer
          ? party.id
          : party is Supplier
          ? party.id
          : '';
      final external = _isSale
          ? '$locationId:$ref'
          : '$locationId:${_value(first.data, 'supplier_invoice_number')}:$ref';
      output.add(
        _TransactionImportDocument(
          reference: ref,
          rowCount: sourceRows.length,
          total: total,
          errors: errors.toSet().toList(),
          payload: {
            'external_key': external,
            'document_ref': ref,
            'source_row_count': sourceRows.length,
            'document_date': documentDate,
            'due_date': dueDate,
            if (_isSale) 'customer_id': partyId else 'supplier_id': partyId,
            if (!_isSale)
              'supplier_invoice_number': _value(
                first.data,
                'supplier_invoice_number',
              ),
            'items': items,
            'additional_charges': additional,
            'round_off': roundOff,
            'initial_payment': initialPayment,
            'payment_method': _value(first.data, 'payment_method').isEmpty
                ? (_isSale ? 'cash' : 'bank')
                : _value(first.data, 'payment_method').toLowerCase(),
            if (_isSale)
              'payment_reference': _value(first.data, 'payment_reference'),
            'notes': _value(first.data, 'notes'),
          },
        ),
      );
    }
    return output;
  }

  Customer? _resolveCustomer(
    List<Customer> customers, {
    required String code,
    required String name,
    required String phone,
  }) {
    final c = code.toLowerCase();
    if (c.isNotEmpty) {
      final found = customers
          .where((e) => e.publicId.toLowerCase() == c)
          .toList();
      if (found.length == 1) return found.first;
    }
    final digits = _digits(phone);
    if (digits.isNotEmpty) {
      final found = customers
          .where((e) => _digits(e.phone ?? '') == digits)
          .toList();
      if (found.length == 1) return found.first;
    }
    final n = name.toLowerCase();
    if (n.isNotEmpty) {
      final found = customers
          .where((e) => e.name.trim().toLowerCase() == n)
          .toList();
      if (found.length == 1) return found.first;
    }
    return null;
  }

  Supplier? _resolveSupplier(
    List<Supplier> suppliers, {
    required String code,
    required String name,
  }) {
    final c = code.toLowerCase();
    if (c.isNotEmpty) {
      final found = suppliers
          .where((e) => e.publicId.toLowerCase() == c)
          .toList();
      if (found.length == 1) return found.first;
    }
    final n = name.toLowerCase();
    if (n.isNotEmpty) {
      final found = suppliers
          .where((e) => e.name.trim().toLowerCase() == n)
          .toList();
      if (found.length == 1) return found.first;
    }
    return null;
  }

  Future<void> _import() async {
    final locationId = _locationId;
    final sourceKey = _sourceKey;
    if (locationId == null || sourceKey == null || _fileName == null) {
      _message('Choose and validate an Excel file first.');
      return;
    }
    final valid = _documents.where((e) => e.errors.isEmpty).toList();
    if (valid.isEmpty) {
      _message('There are no valid documents to import.');
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await _bulk.importTransactions(
        tenantId: widget.session.business.id,
        importType: widget.type,
        locationId: locationId,
        deviceId: widget.session.device?.deviceId,
        sourceName: _fileName!,
        sourceKey: sourceKey,
        documents: valid.map((e) => e.payload).toList(),
      );
      final documents = (response['documents'] as List? ?? const []);
      final failures = documents
          .whereType<Map>()
          .where((e) => e['status'] == 'failed')
          .map((e) => '${e['external_key'] ?? ''}: ${e['error'] ?? 'Failed'}')
          .toList();
      if (!mounted) return;
      setState(() {
        _result =
            '$_label import finished: '
            '${response['success_count'] ?? 0} created • '
            '${response['skipped_count'] ?? 0} already imported • '
            '${response['failed_count'] ?? 0} failed'
            '${failures.isEmpty ? '' : '\n${failures.take(15).join('\n')}'}';
      });
      await _loadHistory();
    } catch (error) {
      _message(_cleanError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locations = LocationScopeService.writableLocations(widget.session);
    final validCount = _documents.where((e) => e.errors.isEmpty).length;
    final invalidCount = _documents.length - validCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                  labelText: 'Store / location',
                ),
                items: locations
                    .map(
                      (l) => DropdownMenuItem(
                        value: l.id,
                        child: Text('${l.code} • ${l.name}'),
                      ),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _locationId = value;
                        _documents = const [];
                        _fileName = null;
                        _sourceKey = null;
                        _result = null;
                      }),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _downloadTemplate,
              icon: const Icon(Icons.download_outlined),
              label: Text('Download $_label Template'),
            ),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _chooseExcel,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Choose Excel'),
            ),
            if (_fileName != null) Chip(label: Text(_fileName!)),
          ],
        ),
        const SizedBox(height: 8),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bulk $_label uses the same transaction engine as manual entry, so stock, tax, payments and accounting are posted together. Serial/batch products are intentionally blocked from bulk import.',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _documents.isEmpty
              ? _emptyState()
              : Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          '$validCount valid',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 14),
                        Text('$invalidCount invalid'),
                        const Spacer(),
                        Text('${_documents.length} documents'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _documents.length,
                        itemBuilder: (_, index) {
                          final doc = _documents[index];
                          final valid = doc.errors.isEmpty;
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                valid
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline,
                                color: valid
                                    ? Colors.green
                                    : Theme.of(context).colorScheme.error,
                              ),
                              title: Text(
                                doc.reference,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                valid
                                    ? '${doc.rowCount} item row(s) • ${widget.session.currencyCode} ${doc.total.toStringAsFixed(2)}'
                                    : doc.errors.join(' • '),
                              ),
                              trailing: Text(valid ? 'READY' : 'FIX'),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 6),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Recent imports',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            children: _history
                .take(8)
                .map(
                  (row) => ListTile(
                    dense: true,
                    title: Text(
                      '${row['source_name'] ?? 'Import'} • ${row['status'] ?? ''}',
                    ),
                    subtitle: Text('${row['created_at'] ?? ''}'),
                    trailing: Text(
                      '${row['success_count'] ?? 0} ok / ${row['failed_count'] ?? 0} failed',
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        if (_result != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SelectableText(
              _result!,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _busy || validCount == 0 ? null : _import,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(
              _busy
                  ? 'Importing…'
                  : 'Import $validCount $_label document${validCount == 1 ? '' : 's'}',
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.table_view_outlined, size: 46),
        const SizedBox(height: 8),
        Text(
          'Download the THQ $_label template, fill it and choose the .xlsx file.',
        ),
        const SizedBox(height: 4),
        const Text(
          'Nothing is posted until validation succeeds and you press Import.',
          style: TextStyle(fontSize: 11),
        ),
      ],
    ),
  );

  String _cell(CellValue? value) => value?.toString().trim() ?? '';

  String _value(Map<String, String> row, String key) => row[key]?.trim() ?? '';

  double? _number(String value) =>
      value.isEmpty ? null : double.tryParse(value.replaceAll(',', ''));

  String? _date(String value, {bool allowBlank = false}) {
    if (value.trim().isEmpty) return allowBlank ? null : null;
    final normalized = value.trim().length >= 10
        ? value.trim().substring(0, 10)
        : value.trim();
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return null;
    return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  String _today() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _digits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  String _cleanError(Object error) {
    var text = error.toString();
    if (text.startsWith('Exception: ')) text = text.substring(11);
    return text;
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }
}

class _SourceRow {
  final int rowNumber;
  final Map<String, String> data;
  const _SourceRow(this.rowNumber, this.data);
}

class _TransactionImportDocument {
  final String reference;
  final int rowCount;
  final Map<String, dynamic> payload;
  final List<String> errors;
  final double total;

  const _TransactionImportDocument({
    required this.reference,
    required this.rowCount,
    required this.payload,
    required this.errors,
    required this.total,
  });
}
