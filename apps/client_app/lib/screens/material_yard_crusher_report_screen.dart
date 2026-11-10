import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../services/aggregate_yard_service.dart';
import '../services/location_scope_service.dart';
import '../services/operational_export_service.dart';
import '../services/staff_load_service.dart';
import '../widgets/record_preview.dart';
import 'aggregate_loads_screen.dart';
import 'material_load_detail_screen.dart';

/// Crusher Material Register / Load Report
///
/// Tailored for quarry and bulk-material yards with the exact register columns:
/// DAET | METERIYAL | CRUSHER | DRIVER | VEHICLE NO | VEHICLE Q | PURCHASING PRICE | TOTTAL
class MaterialYardCrusherReportScreen extends StatefulWidget {
  final ClientSession session;

  const MaterialYardCrusherReportScreen({super.key, required this.session});

  @override
  State<MaterialYardCrusherReportScreen> createState() =>
      _MaterialYardCrusherReportScreenState();
}

class _MaterialYardCrusherReportScreenState
    extends State<MaterialYardCrusherReportScreen> {
  final StaffLoadService _loadService = StaffLoadService();
  final AggregateYardService _yardService = AggregateYardService();
  final OperationalExportService _exportService = OperationalExportService();
  final TextEditingController _searchController = TextEditingController();

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();

  Map<String, dynamic> _context = const {};
  List<Map<String, dynamic>> _rawLoads = const [];
  bool _busy = true;
  String? _error;

  String? _selectedCrusher;
  String? _selectedMaterial;
  String? _selectedVehicle;
  String? _selectedDriver;

  String _sortColumn = 'date';
  bool _sortAscending = false;

  final DateFormat _displayDateFormat = DateFormat('dd-MM-yyyy');

  ClientSession get session => widget.session;
  String get _tenantId => session.business.id;
  String? get _locationId => LocationScopeService.currentForRead(session);

  @override
  void initState() {
    super.initState();
    LocationScopeService.selectedLocationId.addListener(_onLocationChanged);
    _reload();
  }

  @override
  void dispose() {
    LocationScopeService.selectedLocationId.removeListener(_onLocationChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onLocationChanged() {
    if (mounted) _reload();
  }

  Future<void> _reload() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }

    try {
      final contextFuture = _context.isEmpty
          ? _yardService.context(tenantId: _tenantId)
          : Future<Map<String, dynamic>>.value(_context);

      final loadsDataFuture = _loadService.load(
        tenantId: _tenantId,
        action: 'report',
        locationId: _locationId,
        data: {
          'from': StaffLoadService.date(_from),
          'to': StaffLoadService.date(_to),
          if (_selectedVehicle != null) 'vehicle_id': _selectedVehicle,
          if (_selectedDriver != null) 'driver_id': _selectedDriver,
        },
      );

      final results = await Future.wait<Map<String, dynamic>>([
        contextFuture,
        loadsDataFuture,
      ]);
      final contextData = results[0];
      final loadsData = results[1];

      if (!mounted) return;
      setState(() {
        _context = contextData;
        _rawLoads = StaffLoadService.rows(loadsData['loads']);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '') ?? 0.0;
  }

  String _money(double value) {
    if (session.currencyCode == 'INR') {
      return '₹${value.toStringAsFixed(2)}';
    }
    return '${session.currencyCode} ${value.toStringAsFixed(2)}';
  }

  String _cleanQty(double value) {
    if ((value - value.roundToDouble()).abs() < 0.000001) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.0+$'), '');
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    try {
      return DateTime.parse(text);
    } catch (_) {
      return null;
    }
  }

  String _formatDate(dynamic value) {
    final parsed = _parseDate(value);
    if (parsed == null) return value?.toString() ?? '-';
    return _displayDateFormat.format(parsed);
  }

  /// Extracts structured crusher report row from a load record
  Map<String, dynamic> _normalizeRow(Map<String, dynamic> load) {
    final delivery = load['delivery'] is Map
        ? Map<String, dynamic>.from(load['delivery'] as Map)
        : const <String, dynamic>{};

    final purchase = load['purchase'] is Map
        ? Map<String, dynamic>.from(load['purchase'] as Map)
        : const <String, dynamic>{};

    final rawDate = load['load_date']?.toString() ?? '';
    final material = (load['product_name'] ?? 'Bulk Material').toString().trim();
    final crusher = (load['supplier_name'] ?? load['source_name'] ?? 'Crusher / Quarry')
        .toString()
        .trim();
    final driver = (load['driver_name'] ?? 'Unassigned').toString().trim();
    final vehicleNo = (load['vehicle_registration'] ?? 'No Truck').toString().trim();
    final quantity = _number(load['quantity']);
    final unitCode = (load['unit_code'] ?? 'FT').toString().trim().toUpperCase();

    // Deriving Purchasing Price & Total (THQ Pricing Rules v713)
    double purchasingPrice = 0.0;
    double total = 0.0;
    bool hasPrice = false;
    bool isInvoiced = false;
    String? invoiceNumber;

    // 1. Direct Invoice Resolution from migration v713 (aggregate_load_list_v629)
    final invRate = _number(load['invoice_rate']);
    final invAmt = _number(load['invoice_amount']);
    final invNum = load['invoice_number']?.toString();

    if (invRate > 0) {
      purchasingPrice = invRate;
      hasPrice = true;
      isInvoiced = true;
      total = invAmt > 0 ? invAmt : (quantity > 0 ? quantity * invRate : 0.0);
      invoiceNumber = invNum;
    } else if (purchase.isNotEmpty) {
      isInvoiced = true;
      invoiceNumber = purchase['purchase_number']?.toString() ??
          purchase['invoice_number']?.toString();
      final items = (purchase['items'] as List? ?? const []);
      if (items.isNotEmpty && items.first is Map) {
        final it = items.first as Map;
        final itRate = _number(it['unit_cost'] ??
            it['entered_unit_cost'] ??
            it['unit_price'] ??
            it['cost_price']);
        if (itRate > 0) {
          purchasingPrice = itRate;
          hasPrice = true;
        }
      }
      final grandTotal = _number(purchase['grand_total']);
      if (grandTotal > 0) {
        total = grandTotal;
        if (purchasingPrice == 0 && quantity > 0) {
          purchasingPrice = grandTotal / quantity;
          hasPrice = true;
        }
      }
    }

    // 2. Pre-invoice negotiated / delivery rate fallback (suggested buy price)
    if (!hasPrice) {
      if (delivery.containsKey('purchasing_price') &&
          _number(delivery['purchasing_price']) > 0) {
        purchasingPrice = _number(delivery['purchasing_price']);
        hasPrice = true;
      }
      if (delivery.containsKey('purchasing_total') &&
          _number(delivery['purchasing_total']) > 0) {
        total = _number(delivery['purchasing_total']);
        if (purchasingPrice == 0 && quantity > 0) {
          purchasingPrice = total / quantity;
        }
        hasPrice = true;
      }
    }

    // 3. Fallback checks from load costs
    if (!hasPrice) {
      final costs = StaffLoadService.rows(load['costs']);
      for (final cost in costs) {
        final kind = (cost['cost_kind'] ?? '').toString();
        final desc = (cost['description'] ?? '').toString().toLowerCase();
        if (kind == 'other' &&
            (desc.contains('material') || desc.contains('purchase'))) {
          purchasingPrice = _number(cost['rate']);
          total = _number(cost['amount']);
          if (purchasingPrice > 0 || total > 0) {
            hasPrice = true;
            break;
          }
        }
      }
    }

    // 4. Auto-compute between price and total if one was entered and other is 0
    if (total == 0 && purchasingPrice > 0 && quantity > 0) {
      total = quantity * purchasingPrice;
    } else if (purchasingPrice == 0 && total > 0 && quantity > 0) {
      purchasingPrice = total / quantity;
    }

    return {
      'load_id': load['load_id'] ?? load['id'],
      'raw_load': load,
      'raw_date': rawDate,
      'display_date': _formatDate(rawDate),
      'material': material,
      'crusher': crusher,
      'driver': driver,
      'vehicle_no': vehicleNo,
      'quantity': quantity,
      'unit_code': unitCode,
      'quantity_display': '${_cleanQty(quantity)} $unitCode',
      'has_price': hasPrice && purchasingPrice > 0,
      'is_invoiced': isInvoiced,
      'invoice_number': invoiceNumber,
      'purchasing_price': purchasingPrice,
      'total': total,
      'supplier_id': load['supplier_id'],
      'variant_id': load['variant_id'],
      'vehicle_id': load['vehicle_id'],
      'driver_id': load['driver_id'],
      'purchase_id': load['purchase_id'],
      'direction': load['direction'] ?? 'inbound',
      'status': load['status'] ?? 'completed',
    };
  }

  List<Map<String, dynamic>> get _filteredRows {
    final query = _searchController.text.trim().toLowerCase();

    final rows = _rawLoads.map(_normalizeRow).where((row) {
      // Inbound or direct delivery bulk material loads
      if (_selectedCrusher != null && _selectedCrusher!.isNotEmpty) {
        if (row['supplier_id'] != _selectedCrusher &&
            row['crusher'].toString().toLowerCase() !=
                _selectedCrusher!.toLowerCase()) {
          return false;
        }
      }

      if (_selectedMaterial != null && _selectedMaterial!.isNotEmpty) {
        if (row['variant_id'] != _selectedMaterial &&
            row['material'].toString().toLowerCase() !=
                _selectedMaterial!.toLowerCase()) {
          return false;
        }
      }

      if (_selectedVehicle != null && _selectedVehicle!.isNotEmpty) {
        if (row['vehicle_id'] != _selectedVehicle &&
            row['vehicle_no'].toString().toLowerCase() !=
                _selectedVehicle!.toLowerCase()) {
          return false;
        }
      }

      if (_selectedDriver != null && _selectedDriver!.isNotEmpty) {
        if (row['driver_id'] != _selectedDriver &&
            row['driver'].toString().toLowerCase() !=
                _selectedDriver!.toLowerCase()) {
          return false;
        }
      }

      if (query.isNotEmpty) {
        final date = row['display_date'].toString().toLowerCase();
        final mat = row['material'].toString().toLowerCase();
        final cru = row['crusher'].toString().toLowerCase();
        final dri = row['driver'].toString().toLowerCase();
        final veh = row['vehicle_no'].toString().toLowerCase();
        final qty = row['quantity_display'].toString().toLowerCase();
        final price = row['purchasing_price'].toString();
        final tot = row['total'].toString();

        if (!date.contains(query) &&
            !mat.contains(query) &&
            !cru.contains(query) &&
            !dri.contains(query) &&
            !veh.contains(query) &&
            !qty.contains(query) &&
            !price.contains(query) &&
            !tot.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();

    rows.sort((a, b) {
      int cmp = 0;
      switch (_sortColumn) {
        case 'date':
          cmp = (a['raw_date'] as String).compareTo(b['raw_date'] as String);
          break;
        case 'material':
          cmp = (a['material'] as String).compareTo(b['material'] as String);
          break;
        case 'crusher':
          cmp = (a['crusher'] as String).compareTo(b['crusher'] as String);
          break;
        case 'driver':
          cmp = (a['driver'] as String).compareTo(b['driver'] as String);
          break;
        case 'vehicle':
          cmp = (a['vehicle_no'] as String).compareTo(b['vehicle_no'] as String);
          break;
        case 'quantity':
          cmp = (a['quantity'] as double).compareTo(b['quantity'] as double);
          break;
        case 'price':
          cmp = (a['purchasing_price'] as double)
              .compareTo(b['purchasing_price'] as double);
          break;
        case 'total':
          cmp = (a['total'] as double).compareTo(b['total'] as double);
          break;
        default:
          cmp = (a['raw_date'] as String).compareTo(b['raw_date'] as String);
      }
      return _sortAscending ? cmp : -cmp;
    });

    return rows;
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: 'Select Crusher Report Period',
    );

    if (picked != null && mounted) {
      setState(() {
        _from = picked.start;
        _to = picked.end;
      });
      await _reload();
    }
  }

  void _setPreset(String preset) {
    final now = DateTime.now();
    DateTime start;
    DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (preset) {
      case 'today':
        start = DateTime(now.year, now.month, now.day);
        break;
      case 'yesterday':
        final y = now.subtract(const Duration(days: 1));
        start = DateTime(y.year, y.month, y.day);
        end = DateTime(y.year, y.month, y.day, 23, 59, 59);
        break;
      case 'this_month':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'last_30_days':
        start = now.subtract(const Duration(days: 30));
        break;
      default:
        start = DateTime(now.year, now.month, 1);
    }

    setState(() {
      _from = start;
      _to = end;
    });
    _reload();
  }

  /// Quick editor to safely record / adjust purchasing price and total on a load
  Future<void> _editPriceDialog(Map<String, dynamic> row) async {
    final loadId = row['load_id']?.toString() ?? '';
    if (loadId.isEmpty) return;

    final priceCtrl = TextEditingController(
      text: (row['purchasing_price'] as double) > 0
          ? _cleanQty(row['purchasing_price'] as double)
          : '',
    );
    final totalCtrl = TextEditingController(
      text: (row['total'] as double) > 0
          ? (row['total'] as double).toStringAsFixed(2)
          : '',
    );

    final quantity = row['quantity'] as double;
    final unitCode = row['unit_code'] as String;

    void updateAuto(bool fromPrice) {
      if (fromPrice) {
        final p = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
        if (p > 0 && quantity > 0) {
          totalCtrl.text = (p * quantity).toStringAsFixed(2);
        }
      } else {
        final t = double.tryParse(totalCtrl.text.trim()) ?? 0.0;
        if (t > 0 && quantity > 0) {
          priceCtrl.text = _cleanQty(t / quantity);
        }
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Edit Rate: ${row['material']}',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Crusher: ${row['crusher']}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                          Text(
                            'Vehicle: ${row['vehicle_no']} • Driver: ${row['driver']}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${_cleanQty(quantity)} $unitCode',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(ctx).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Purchasing Price / Rate (per $unitCode)',
                  hintText: 'e.g. 42 or 35000',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calculate_outlined, size: 18),
                    tooltip: 'Calculate Total',
                    onPressed: () => updateAuto(true),
                  ),
                ),
                onChanged: (_) => updateAuto(true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: totalCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Total Purchasing Amount (${session.currencyCode})',
                  hintText: 'e.g. 35000',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calculate_outlined, size: 18),
                    tooltip: 'Calculate Unit Rate',
                    onPressed: () => updateAuto(false),
                  ),
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
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Save Rate'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final newPrice = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
    final newTotal = double.tryParse(totalCtrl.text.trim()) ?? (newPrice * quantity);

    try {
      await _loadService.load(
        tenantId: _tenantId,
        action: 'delivery',
        data: {
          'load_id': loadId,
          'purchasing_price': newPrice,
          'purchasing_total': newTotal,
        },
      );

      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          const SnackBar(content: Text('Purchasing rate saved successfully.')),
        );
        await _reload();
      }
    } catch (e) {
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text('Error saving rate: $e')),
        );
      }
    }
  }

  /// Exports table directly to Excel matching the exact Google Sheets format
  Future<void> _exportToExcel() async {
    final rows = _filteredRows;
    if (rows.isEmpty) {
      ThqNotify.showSnackBar(
        context,
        const SnackBar(content: Text('No data to export.')),
      );
      return;
    }

    try {
      final excel = Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet();
      const sheetName = 'Crusher Register';
      if (defaultSheet != null) {
        excel.rename(defaultSheet, sheetName);
      }

      final sheet = excel[sheetName];

      // Title & Metadata
      sheet.appendRow([
        TextCellValue('CRUSHER MATERIAL REGISTER • ${session.business.name.toUpperCase()}'),
      ]);
      sheet.appendRow([
        TextCellValue(
          'Period: ${_formatDate(_from)} to ${_formatDate(_to)} | Generated: ${_displayDateFormat.format(DateTime.now())}',
        ),
      ]);
      sheet.appendRow([TextCellValue('')]); // Blank line

      // Exact Table Headers matching User's Spreadsheet
      sheet.appendRow([
        TextCellValue('DAET'),
        TextCellValue('METERIYAL'),
        TextCellValue('CRUSHER'),
        TextCellValue('DRIVER'),
        TextCellValue('VEHICLE NO'),
        TextCellValue('VEHICLE Q'),
        TextCellValue('PURCHASING PRICE'),
        TextCellValue('TOTTAL'),
      ]);

      double totalQty = 0.0;
      double pricedQty = 0.0;
      double grandTotal = 0.0;

      // Data Rows
      for (final r in rows) {
        final q = r['quantity'] as double;
        final hasPrice = r['has_price'] as bool? ?? false;
        final p = r['purchasing_price'] as double;
        final t = r['total'] as double;

        totalQty += q;
        if (hasPrice && p > 0) {
          pricedQty += q;
          grandTotal += t;
        }

        sheet.appendRow([
          TextCellValue(r['display_date'].toString()),
          TextCellValue(r['material'].toString()),
          TextCellValue(r['crusher'].toString()),
          TextCellValue(r['driver'].toString()),
          TextCellValue(r['vehicle_no'].toString()),
          TextCellValue(r['quantity_display'].toString()),
          hasPrice && p > 0 ? DoubleCellValue(p) : TextCellValue('Rate pending'),
          hasPrice && t > 0 ? DoubleCellValue(t) : TextCellValue('Not invoiced'),
        ]);
      }

      final weightedAvg = pricedQty > 0 ? (grandTotal / pricedQty) : 0.0;

      // Summary Total Row (Formula: Total Purchase Value ÷ Total Purchased Quantity of priced transactions)
      sheet.appendRow([
        TextCellValue('TOTAL'),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('${_cleanQty(totalQty)} FT'),
        TextCellValue(
          weightedAvg > 0 ? _cleanQty(weightedAvg) : 'Rate pending',
        ),
        DoubleCellValue(grandTotal),
      ]);

      final bytes = excel.save();
      if (bytes == null) throw StateError('Failed to encode Excel file.');

      final fileName =
          'Crusher_Register_${StaffLoadService.date(_from)}_${StaffLoadService.date(_to)}';

      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );

      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text('Excel report saved: $fileName.xlsx')),
        );
      }
    } catch (e) {
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  /// Copies table in TSV (Tab Separated) format to easily paste straight into Google Sheets
  Future<void> _copyForGoogleSheets() async {
    final rows = _filteredRows;
    if (rows.isEmpty) return;

    final buffer = StringBuffer();
    // Header
    buffer.writeln(
      'DAET\tMETERIYAL\tCRUSHER\tDRIVER\tVEHICLE NO\tVEHICLE Q\tPURCHASING PRICE\tTOTTAL',
    );

    double totalQty = 0.0;
    double pricedQty = 0.0;
    double grandTotal = 0.0;

    for (final r in rows) {
      final q = r['quantity'] as double;
      final hasPrice = r['has_price'] as bool? ?? false;
      final p = r['purchasing_price'] as double;
      final t = r['total'] as double;

      totalQty += q;
      if (hasPrice && p > 0) {
        pricedQty += q;
        grandTotal += t;
      }

      buffer.writeln(
        '${r['display_date']}\t${r['material']}\t${r['crusher']}\t${r['driver']}\t${r['vehicle_no']}\t${r['quantity_display']}\t${hasPrice && p > 0 ? _cleanQty(p) : 'Rate pending'}\t${hasPrice && t > 0 ? t.toStringAsFixed(2) : 'Not invoiced'}',
      );
    }

    // Total row
    final weightedAvg = pricedQty > 0 ? (grandTotal / pricedQty) : 0.0;
    buffer.writeln(
      'TOTAL\t\t\t\t\t${_cleanQty(totalQty)} FT\t${weightedAvg > 0 ? _cleanQty(weightedAvg) : 'Rate pending'}\t${grandTotal.toStringAsFixed(2)}',
    );

    await Clipboard.setData(ClipboardData(text: buffer.toString()));

    if (mounted) {
      ThqNotify.showSnackBar(
        context,
        const SnackBar(
          content: Text('Copied to clipboard! Paste directly into Google Sheets or Excel.'),
        ),
      );
    }
  }

  /// Print / PDF export
  Future<void> _printReport() async {
    final rows = _filteredRows;
    if (rows.isEmpty) return;

    double totalQty = 0.0;
    double pricedQty = 0.0;
    double grandTotal = 0.0;
    for (final r in rows) {
      final q = r['quantity'] as double;
      final hasPrice = r['has_price'] as bool? ?? false;
      final p = r['purchasing_price'] as double;
      final t = r['total'] as double;
      totalQty += q;
      if (hasPrice && p > 0) {
        pricedQty += q;
        grandTotal += t;
      }
    }
    final weightedAvg = pricedQty > 0 ? (grandTotal / pricedQty) : 0.0;

    final dataset = {
      'overview': {
        'Report': 'Crusher Material Register',
        'Business': session.business.name,
        'Period': '${_formatDate(_from)} to ${_formatDate(_to)}',
        'Total Loads': rows.length,
        'Total Quantity': '${_cleanQty(totalQty)} FT',
        'Priced Quantity': '${_cleanQty(pricedQty)} FT',
        'Unpriced Quantity': '${_cleanQty(totalQty - pricedQty)} FT',
        'Invoiced Amount': _money(grandTotal),
        'Weighted Average Rate': weightedAvg > 0 ? '${_money(weightedAvg)} / FT' : 'Rate pending',
      },
      'crusher_loads': [
        for (final r in rows)
          {
            'Date': r['display_date'],
            'Material': r['material'],
            'Crusher': r['crusher'],
            'Driver': r['driver'],
            'Vehicle': r['vehicle_no'],
            'Quantity': r['quantity_display'],
            'Price': (r['has_price'] as bool? ?? false) && (r['purchasing_price'] as double) > 0
                ? _cleanQty(r['purchasing_price'] as double)
                : 'Rate pending',
            'Total': (r['has_price'] as bool? ?? false) && (r['total'] as double) > 0
                ? (r['total'] as double).toStringAsFixed(2)
                : 'Not invoiced',
          },
      ],
    };

    await _exportService.printDataset('Crusher_Material_Register', dataset);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = _filteredRows;

    // Totals for summary ribbon (THQ Pricing Rules v713)
    final totalLoads = rows.length;
    final totalQty = rows.fold<double>(0.0, (s, r) => s + (r['quantity'] as double));

    final pricedRows = rows.where((r) => (r['has_price'] as bool? ?? false) && (r['purchasing_price'] as double? ?? 0.0) > 0).toList();
    final pricedQty = pricedRows.fold<double>(0.0, (s, r) => s + (r['quantity'] as double));
    final pricedTotal = pricedRows.fold<double>(0.0, (s, r) => s + (r['total'] as double));
    final weightedAvgRate = pricedQty > 0 ? (pricedTotal / pricedQty) : 0.0;

    final unpricedRows = rows.where((r) => !(r['has_price'] as bool? ?? false) || (r['purchasing_price'] as double? ?? 0.0) <= 0).toList();
    final unpricedQty = unpricedRows.fold<double>(0.0, (s, r) => s + (r['quantity'] as double));
    final crushersCount = rows.map((r) => r['crusher']).toSet().length;

    // Filter Options
    final crusherOptions = StaffLoadService.rows(_context['suppliers'])
        .map((s) => s['name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()..sort();

    final materialOptions = StaffLoadService.rows(_context['products'])
        .map((p) => p['name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()..sort();

    final vehicleOptions = StaffLoadService.rows(_context['vehicles'])
        .map((v) => v['registration_number']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()..sort();

    final driverOptions = StaffLoadService.rows(_context['drivers'])
        .map((d) => d['name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()..sort();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Crusher Material Register',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'Material Yard • Inbound loads, quantities, purchasing rates & totals',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _busy ? null : _reload,
          ),
          IconButton(
            tooltip: 'Copy for Google Sheets',
            icon: const Icon(Icons.content_copy_rounded),
            onPressed: rows.isEmpty ? null : _copyForGoogleSheets,
          ),
          IconButton(
            tooltip: 'Print / PDF',
            icon: const Icon(Icons.print_outlined),
            onPressed: rows.isEmpty ? null : _printReport,
          ),
          FilledButton.tonalIcon(
            onPressed: rows.isEmpty ? null : _exportToExcel,
            icon: const Icon(Icons.table_view_rounded, size: 16),
            label: const Text('Export Excel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AggregateLoadsScreen(
                    session: session,
                    initialCreateDirection: 'inbound',
                  ),
                ),
              );
              if (mounted) _reload();
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Receive Load'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // Filter & Control Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Date Range Button
                OutlinedButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.date_range_outlined, size: 16),
                  label: Text('${_formatDate(_from)} — ${_formatDate(_to)}'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),

                // Quick Date Presets
                Wrap(
                  spacing: 4,
                  children: [
                    ChoiceChip(
                      label: const Text('Today', style: TextStyle(fontSize: 11)),
                      selected: StaffLoadService.date(_from) ==
                              StaffLoadService.date(DateTime.now()) &&
                          StaffLoadService.date(_to) ==
                              StaffLoadService.date(DateTime.now()),
                      onSelected: (_) => _setPreset('today'),
                    ),
                    ChoiceChip(
                      label: const Text('Yesterday', style: TextStyle(fontSize: 11)),
                      selected: false,
                      onSelected: (_) => _setPreset('yesterday'),
                    ),
                    ChoiceChip(
                      label: const Text('This Month', style: TextStyle(fontSize: 11)),
                      selected: _from.day == 1 &&
                          _from.month == DateTime.now().month &&
                          _from.year == DateTime.now().year,
                      onSelected: (_) => _setPreset('this_month'),
                    ),
                    ChoiceChip(
                      label: const Text('Last 30 Days', style: TextStyle(fontSize: 11)),
                      selected: false,
                      onSelected: (_) => _setPreset('last_30_days'),
                    ),
                  ],
                ),

                // Crusher Dropdown
                if (crusherOptions.isNotEmpty)
                  SizedBox(
                    width: 160,
                    height: 36,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedCrusher ?? '',
                      isExpanded: true,
                      dropdownColor: scheme.surface,
                      decoration: const InputDecoration(
                        labelText: 'Crusher',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      ),
                      style: TextStyle(fontSize: 12, color: scheme.onSurface),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(
                            'All Crushers',
                            style: TextStyle(fontSize: 12, color: scheme.onSurface),
                          ),
                        ),
                        for (final c in crusherOptions)
                          DropdownMenuItem(
                            value: c,
                            child: Text(
                              c,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: scheme.onSurface),
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() => _selectedCrusher = (v == null || v.isEmpty) ? null : v);
                      },
                    ),
                  ),

                // Material Dropdown
                if (materialOptions.isNotEmpty)
                  SizedBox(
                    width: 160,
                    height: 36,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedMaterial ?? '',
                      isExpanded: true,
                      dropdownColor: scheme.surface,
                      decoration: const InputDecoration(
                        labelText: 'Material',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      ),
                      style: TextStyle(fontSize: 12, color: scheme.onSurface),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(
                            'All Materials',
                            style: TextStyle(fontSize: 12, color: scheme.onSurface),
                          ),
                        ),
                        for (final m in materialOptions)
                          DropdownMenuItem(
                            value: m,
                            child: Text(
                              m,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: scheme.onSurface),
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() => _selectedMaterial = (v == null || v.isEmpty) ? null : v);
                      },
                    ),
                  ),

                // Vehicle Dropdown
                if (vehicleOptions.isNotEmpty)
                  SizedBox(
                    width: 140,
                    height: 36,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedVehicle ?? '',
                      isExpanded: true,
                      dropdownColor: scheme.surface,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      ),
                      style: TextStyle(fontSize: 12, color: scheme.onSurface),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(
                            'All Trucks',
                            style: TextStyle(fontSize: 12, color: scheme.onSurface),
                          ),
                        ),
                        for (final v in vehicleOptions)
                          DropdownMenuItem(
                            value: v,
                            child: Text(
                              v,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: scheme.onSurface),
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() => _selectedVehicle = (v == null || v.isEmpty) ? null : v);
                      },
                    ),
                  ),

                // Driver Dropdown
                if (driverOptions.isNotEmpty)
                  SizedBox(
                    width: 140,
                    height: 36,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedDriver ?? '',
                      isExpanded: true,
                      dropdownColor: scheme.surface,
                      decoration: const InputDecoration(
                        labelText: 'Driver',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      ),
                      style: TextStyle(fontSize: 12, color: scheme.onSurface),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(
                            'All Drivers',
                            style: TextStyle(fontSize: 12, color: scheme.onSurface),
                          ),
                        ),
                        for (final d in driverOptions)
                          DropdownMenuItem(
                            value: d,
                            child: Text(
                              d,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: scheme.onSurface),
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() => _selectedDriver = (v == null || v.isEmpty) ? null : v);
                      },
                    ),
                  ),

                // Search Field
                SizedBox(
                  width: 180,
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search register...',
                      prefixIcon: const Icon(Icons.search, size: 16),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    ),
                    style: TextStyle(fontSize: 12, color: scheme.onSurface),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),

          // Compact KPI Summary Ribbon (Futuristic, compact THQ ERP design - Rules 9 & 10)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              children: [
                _SummaryMetric(
                  icon: Icons.local_shipping_outlined,
                  label: 'TOTAL LOADS',
                  value: unpricedRows.isEmpty
                      ? '$totalLoads'
                      : '$totalLoads (${pricedRows.length} priced, ${unpricedRows.length} pending)',
                ),
                _separator(scheme),
                _SummaryMetric(
                  icon: Icons.square_foot_outlined,
                  label: 'TOTAL QUANTITY',
                  value: '${_cleanQty(totalQty)} FT',
                ),
                _separator(scheme),
                _SummaryMetric(
                  icon: Icons.currency_rupee_rounded,
                  label: 'INVOICED VALUE',
                  value: _money(pricedTotal),
                  valueColor: scheme.primary,
                ),
                _separator(scheme),
                _SummaryMetric(
                  icon: Icons.analytics_outlined,
                  label: 'WEIGHTED AVG RATE',
                  value: weightedAvgRate > 0 ? '${_money(weightedAvgRate)} / FT' : 'Rate pending',
                ),
                if (unpricedRows.isNotEmpty) ...[
                  _separator(scheme),
                  _SummaryMetric(
                    icon: Icons.pending_actions_outlined,
                    label: 'RATE PENDING',
                    value: '${_cleanQty(unpricedQty)} FT',
                    valueColor: const Color(0xFFC06200),
                  ),
                ],
                _separator(scheme),
                _SummaryMetric(
                  icon: Icons.factory_outlined,
                  label: 'CRUSHERS',
                  value: '$crushersCount',
                ),
                const Spacer(),
                Text(
                  'Scope: ${LocationScopeService.scopeLabel(session)}',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

          // Error banner
          if (_error != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: scheme.errorContainer,
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
                    ),
                  ),
                  TextButton(onPressed: _reload, child: const Text('Retry')),
                ],
              ),
            ),

          // Main Table Area
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.table_chart_outlined,
                                size: 48, color: scheme.onSurfaceVariant.withValues(alpha: .5)),
                            const SizedBox(height: 12),
                            const Text(
                              'No crusher loads found for this period and filters.',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Receive an inbound load or adjust the date range.',
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.tonalIcon(
                              onPressed: () => _setPreset('this_month'),
                              icon: const Icon(Icons.calendar_today, size: 14),
                              label: const Text('Show This Month'),
                            ),
                          ],
                        ),
                      )
                    : _buildTable(rows, scheme, totalQty, weightedAvgRate, pricedTotal),
          ),
        ],
      ),
    );
  }

  Widget _separator(ColorScheme scheme) => Container(
        height: 24,
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: scheme.outlineVariant,
      );

  Widget _buildTable(
    List<Map<String, dynamic>> rows,
    ColorScheme scheme,
    double totalQty,
    double avgRate,
    double grandTotal,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowHeight: 40,
                  dataRowMinHeight: 38,
                  dataRowMaxHeight: 46,
                  horizontalMargin: 12,
                  columnSpacing: 18,
                  headingRowColor: WidgetStateProperty.all(
                    scheme.surfaceContainerHighest.withValues(alpha: .4),
                  ),
                  columns: [
                    // 1. DAET
                    DataColumn(
                      label: _headerCell('DAET', 'date'),
                      onSort: (colIndex, ascending) => _onSort('date'),
                    ),
                    // 2. METERIYAL
                    DataColumn(
                      label: _headerCell('METERIYAL', 'material'),
                      onSort: (colIndex, ascending) => _onSort('material'),
                    ),
                    // 3. CRUSHER
                    DataColumn(
                      label: _headerCell('CRUSHER', 'crusher'),
                      onSort: (colIndex, ascending) => _onSort('crusher'),
                    ),
                    // 4. DRIVER
                    DataColumn(
                      label: _headerCell('DRIVER', 'driver'),
                      onSort: (colIndex, ascending) => _onSort('driver'),
                    ),
                    // 5. VEHICLE NO
                    DataColumn(
                      label: _headerCell('VEHICLE NO', 'vehicle'),
                      onSort: (colIndex, ascending) => _onSort('vehicle'),
                    ),
                    // 6. VEHICLE Q
                    DataColumn(
                      numeric: true,
                      label: _headerCell('VEHICLE Q', 'quantity'),
                      onSort: (colIndex, ascending) => _onSort('quantity'),
                    ),
                    // 7. PURCHASING PRICE
                    DataColumn(
                      numeric: true,
                      label: _headerCell('PURCHASING PRICE', 'price'),
                      onSort: (colIndex, ascending) => _onSort('price'),
                    ),
                    // 8. TOTTAL
                    DataColumn(
                      numeric: true,
                      label: _headerCell('TOTTAL', 'total'),
                      onSort: (colIndex, ascending) => _onSort('total'),
                    ),
                    // Actions Column
                    const DataColumn(label: Text('ACTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  ],
                  rows: [
                    // Data Rows
                    for (final r in rows)
                      DataRow(
                        cells: [
                          // DAET
                          DataCell(
                            Text(
                              r['display_date'].toString(),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                          // METERIYAL
                          DataCell(
                            Text(
                              r['material'].toString(),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                          // CRUSHER
                          DataCell(
                            Text(
                              r['crusher'].toString(),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          // DRIVER
                          DataCell(
                            Text(
                              r['driver'].toString(),
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                            ),
                          ),
                          // VEHICLE NO
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest.withValues(alpha: .5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                r['vehicle_no'].toString(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                          // VEHICLE Q
                          DataCell(
                            Text(
                              r['quantity_display'].toString(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          // PURCHASING PRICE (THQ Rule 4: Rate pending badge)
                          DataCell(
                            InkWell(
                              onTap: () => _editPriceDialog(r),
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: (r['has_price'] as bool? ?? false) && (r['purchasing_price'] as double) > 0
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _cleanQty(r['purchasing_price'] as double),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: scheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.edit_outlined,
                                            size: 13,
                                            color: scheme.primary.withValues(alpha: .7),
                                          ),
                                        ],
                                      )
                                    : Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF8B00).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: const Color(0xFFFF8B00).withValues(alpha: 0.4),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Text(
                                              'Rate pending',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFFC06200),
                                              ),
                                            ),
                                            SizedBox(width: 3),
                                            Icon(
                                              Icons.edit_outlined,
                                              size: 12,
                                              color: Color(0xFFC06200),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          // TOTTAL (THQ Rule 4: Not invoiced)
                          DataCell(
                            (r['has_price'] as bool? ?? false) && (r['total'] as double) > 0
                                ? Text(
                                    (r['total'] as double).toStringAsFixed(2),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.primary,
                                    ),
                                  )
                                : Text(
                                    'Not invoiced',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                                    ),
                                  ),
                          ),
                          // ACTIONS
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                                  tooltip: 'Edit Rate & Total',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _editPriceDialog(r),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.visibility_outlined, size: 16),
                                  tooltip: 'View Load Ticket',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    final loadId = r['load_id']?.toString() ?? '';
                                    if (loadId.isNotEmpty) {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => MaterialLoadDetailScreen(
                                            session: session,
                                            loadId: loadId,
                                          ),
                                        ),
                                      );
                                    } else {
                                      RecordPreview.show(
                                        context,
                                        title: 'Crusher Load Record',
                                        record: r['raw_load'] as Map<String, dynamic>,
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                    // Sticky / Bottom TOTAL Row (Matching Excel / Google Sheets format)
                    DataRow(
                      color: WidgetStateProperty.all(
                        scheme.primaryContainer.withValues(alpha: .25),
                      ),
                      cells: [
                        const DataCell(
                          Text(
                            'TOTAL',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '${rows.length} Loads',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const DataCell(Text('')),
                        const DataCell(Text('')),
                        const DataCell(Text('')),
                        DataCell(
                          Text(
                            '${_cleanQty(totalQty)} FT',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            avgRate > 0 ? 'Avg ${_cleanQty(avgRate)}' : '',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            grandTotal.toStringAsFixed(2),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        const DataCell(Text('')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _headerCell(String title, String columnKey) {
    final isSorted = _sortColumn == columnKey;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: isSorted ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        if (isSorted) ...[
          const SizedBox(width: 3),
          Icon(
            _sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 13,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: valueColor ?? scheme.onSurface,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
