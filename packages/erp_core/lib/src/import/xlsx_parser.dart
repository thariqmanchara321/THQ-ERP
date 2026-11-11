import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

/// Parser for Excel `.xlsx` workbooks.
///
/// Enumerates sheets, handles cell types cleanly, filters blank rows,
/// and prevents loss of whole-number barcode identifiers.
class SmartXlsxParser {
  const SmartXlsxParser();

  /// Lists the names of all worksheets in the workbook.
  List<String> getWorksheetNames(Uint8List bytes) {
    try {
      final workbook = xl.Excel.decodeBytes(bytes);
      return workbook.tables.keys.toList();
    } catch (_) {
      return const [];
    }
  }

  /// Parses the specified worksheet (or the first worksheet) into rows of strings.
  List<List<String>> parseBytes(
    Uint8List bytes, {
    String? sheetName,
  }) {
    final workbook = xl.Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) return const [];

    final targetSheet = sheetName ?? workbook.tables.keys.first;
    final table = workbook.tables[targetSheet];
    if (table == null || table.rows.isEmpty) return const [];

    final result = <List<String>>[];

    for (final rawRow in table.rows) {
      final rowStrings = <String>[];
      var hasContent = false;

      for (final cell in rawRow) {
        final str = _formatCellValue(cell?.value);
        if (str.isNotEmpty) hasContent = true;
        rowStrings.add(str);
      }

      if (hasContent) {
        // Trim trailing empty cells
        while (rowStrings.isNotEmpty && rowStrings.last.isEmpty) {
          rowStrings.removeLast();
        }
        if (rowStrings.isNotEmpty) {
          result.add(rowStrings);
        }
      }
    }

    return result;
  }

  /// Converts an Excel cell value into a clean string representation.
  String _formatCellValue(dynamic cellValue) {
    if (cellValue == null) return '';

    if (cellValue is xl.TextCellValue) {
      return cellValue.value.text?.trim() ?? '';
    }
    if (cellValue is xl.IntCellValue) {
      return cellValue.value.toString();
    }
    if (cellValue is xl.DoubleCellValue) {
      final d = cellValue.value;
      // If double is exact whole number, format without .0 to preserve code
      if (d == d.roundToDouble() && !d.isInfinite && !d.isNaN) {
        return d.toInt().toString();
      }
      return d.toString();
    }
    if (cellValue is xl.BoolCellValue) {
      return cellValue.value ? 'true' : 'false';
    }
    if (cellValue is xl.DateCellValue) {
      return cellValue.asDateTimeLocal().toIso8601String().split('T').first;
    }
    if (cellValue is xl.DateTimeCellValue) {
      return cellValue.asDateTimeLocal().toIso8601String();
    }
    if (cellValue is xl.TimeCellValue) {
      return cellValue.asDuration().toString();
    }
    if (cellValue is xl.FormulaCellValue) {
      return cellValue.formula;
    }

    // Fallback for primitive or legacy objects
    final raw = cellValue.toString().trim();
    return raw;
  }
}
