import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

/// Generates standard, downloadable CSV and XLSX product catalogue templates.
class SampleTemplateGenerator {
  const SampleTemplateGenerator();

  static const List<String> headers = [
    'Product Name',
    'SKU',
    'Barcode',
    'Description',
    'Category',
    'Brand',
    'Unit',
    'Selling Price',
    'Cost Price',
    'List Price',
    'Tax Rate',
    'Reorder Level',
    'Part Number',
  ];

  static const List<List<String>> sampleRows = [
    [
      'UltraTech Cement 50kg',
      'SKU-CEM-50',
      '8901030382910',
      'Standard Grade 53 Portland Cement bag',
      'Cement & Concrete',
      'UltraTech',
      'BAG',
      '380.00',
      '310.00',
      '410.00',
      '18',
      '50',
      'UT-CEM-53',
    ],
    [
      'Blue Metal Aggregate 20mm',
      'SKU-AGG-20',
      '8901030382927',
      'Crushed granite stone aggregate for structural slab',
      'Aggregates',
      'Blackstone',
      'CFT',
      '32.00',
      '24.00',
      '36.00',
      '5',
      '100',
      'AGG-20MM',
    ],
    [
      'Manufactured Sand (M-Sand)',
      'SKU-SAND-01',
      '8901030382934',
      'High grade washed concrete plaster sand',
      'Aggregates',
      'Tenzo Quarry',
      'CFT',
      '28.00',
      '20.00',
      '32.00',
      '5',
      '200',
      'MSAND-GR',
    ],
    [
      'Industrial Safety Helmet',
      'SKU-SAFE-01',
      '8901030382941',
      'Yellow HDPE ratchet suspension head protection',
      'Safety Equipment',
      'Karam',
      'PCS',
      '250.00',
      '180.00',
      '299.00',
      '18',
      '20',
      'KRM-HLM-Y',
    ],
  ];

  /// Generates a valid UTF-8 CSV template string.
  String generateCsv() {
    final buffer = StringBuffer();
    // Header
    buffer.writeln(headers.map(_quoteCsv).join(','));
    // Rows
    for (final row in sampleRows) {
      buffer.writeln(row.map(_quoteCsv).join(','));
    }
    return buffer.toString();
  }

  /// Generates valid UTF-8 CSV template bytes with BOM.
  Uint8List generateCsvBytes() {
    final csvString = generateCsv();
    final utf8Bytes = utf8.encode(csvString);
    // Add UTF-8 BOM so Excel opens with proper encoding
    final result = Uint8List(3 + utf8Bytes.length);
    result[0] = 0xEF;
    result[1] = 0xBB;
    result[2] = 0xBF;
    result.setRange(3, result.length, utf8Bytes);
    return result;
  }

  /// Generates an Excel `.xlsx` workbook template with formatted cells.
  Uint8List generateXlsxBytes() {
    final excel = xl.Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Products';
    final sheet = excel[sheetName];

    // Append headers
    sheet.appendRow(
      headers.map((h) => xl.TextCellValue(h)).toList(),
    );

    // Append sample rows
    for (final row in sampleRows) {
      sheet.appendRow(
        row.map((cell) => xl.TextCellValue(cell)).toList(),
      );
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  static String _quoteCsv(String val) {
    if (val.contains(',') || val.contains('"') || val.contains('\n')) {
      return '"${val.replaceAll('"', '""')}"';
    }
    return val;
  }
}
