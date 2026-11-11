import 'dart:convert';
import 'dart:typed_data';

/// High-performance RFC 4180-compliant pure-Dart CSV parser.
///
/// Handles quotes, escaped quotes (""), delimiters within quotes,
/// multiline cells, UTF-8 BOM, and preserves leading zeros as text.
class SmartCsvParser {
  const SmartCsvParser();

  /// Parses raw CSV bytes into a 2D table of strings.
  List<List<String>> parseBytes(
    Uint8List bytes, {
    String? explicitDelimiter,
  }) {
    // 1. Decode UTF-8 with BOM stripping
    String content;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      content = utf8.decode(bytes.sublist(3));
    } else {
      content = utf8.decode(bytes, allowMalformed: true);
    }

    return parseString(content, explicitDelimiter: explicitDelimiter);
  }

  /// Parses CSV string content into rows and columns.
  List<List<String>> parseString(
    String content, {
    String? explicitDelimiter,
  }) {
    if (content.isEmpty) return const [];

    // Strip leading UTF-8 BOM if present as a character
    var text = content;
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }

    final delimiter = explicitDelimiter ?? _detectDelimiter(text);
    final delimiterCode = delimiter.codeUnitAt(0);
    const quoteCode = 34; // '"'
    const crCode = 13; // '\r'
    const lfCode = 10; // '\n'

    final rows = <List<String>>[];
    var currentRow = <String>[];
    final currentCell = StringBuffer();

    var inQuotes = false;
    final length = text.length;

    for (var i = 0; i < length; i++) {
      final c = text.codeUnitAt(i);

      if (inQuotes) {
        if (c == quoteCode) {
          // Check for escaped quote: ""
          if (i + 1 < length && text.codeUnitAt(i + 1) == quoteCode) {
            currentCell.write('"');
            i++; // skip second quote
          } else {
            inQuotes = false;
          }
        } else {
          currentCell.writeCharCode(c);
        }
      } else {
        if (c == quoteCode) {
          inQuotes = true;
        } else if (c == delimiterCode) {
          currentRow.add(currentCell.toString().trim());
          currentCell.clear();
        } else if (c == crCode || c == lfCode) {
          // Check for CRLF
          if (c == crCode && i + 1 < length && text.codeUnitAt(i + 1) == lfCode) {
            i++;
          }
          currentRow.add(currentCell.toString().trim());
          currentCell.clear();

          // Push row if not entirely blank
          if (_isNonEmptyRow(currentRow)) {
            rows.add(currentRow);
          }
          currentRow = <String>[];
        } else {
          currentCell.writeCharCode(c);
        }
      }
    }

    // Capture any trailing cell and row
    if (currentCell.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(currentCell.toString().trim());
      if (_isNonEmptyRow(currentRow)) {
        rows.add(currentRow);
      }
    }

    return rows;
  }

  /// Automatically senses whether the delimiter is comma, semicolon, or tab.
  String _detectDelimiter(String text) {
    var inQuotes = false;
    var commas = 0;
    var semicolons = 0;
    var tabs = 0;

    final limit = text.length > 4096 ? 4096 : text.length;

    for (var i = 0; i < limit; i++) {
      final c = text[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes) {
        if (c == ',') commas++;
        if (c == ';') semicolons++;
        if (c == '\t') tabs++;
      }
    }

    if (semicolons > commas && semicolons > tabs) return ';';
    if (tabs > commas && tabs > semicolons) return '\t';
    return ',';
  }

  bool _isNonEmptyRow(List<String> row) {
    for (final cell in row) {
      if (cell.isNotEmpty) return true;
    }
    return false;
  }
}
