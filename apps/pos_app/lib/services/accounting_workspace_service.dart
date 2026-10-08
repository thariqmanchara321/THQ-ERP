import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Reports and exports use the same immutable query and column contract.
class AccountingWorkspaceService {
  final String tenantId;
  final String? locationId;
  final ThqAccountingLoader? fetch;
  AccountingWorkspaceService(this.tenantId, this.locationId, {this.fetch});
  Future<ThqAccountingResult> load(ThqAccountingQuery query) async {
    if (fetch != null) return fetch!(query);
    final response = await Supabase.instance.client.rpc(
      'accounting_workspace_v702',
      params: query.parameters(tenantId, locationId),
    );
    return ThqAccountingResult(accountingMap(response));
  }

  Future<ThqAccountingResult> all(ThqAccountingQuery query) async {
    final first = await load(query.copyWith(offset: 0, limit: 500));
    final rows = [...first.rows];
    for (var offset = rows.length; offset < first.total;) {
      final page = await load(query.copyWith(offset: offset, limit: 500));
      if (page.total != first.total ||
          page.rows.isEmpty ||
          page.data['snapshot_token'] != first.data['snapshot_token']) {
        throw StateError(
          'Accounting data changed during export. Refresh and export again.',
        );
      }
      rows.addAll(page.rows);
      offset += page.rows.length;
    }
    if (rows.length != first.total) {
      throw StateError('Incomplete accounting export.');
    }
    return ThqAccountingResult({...first.data, 'rows': rows});
  }

  static String display(
    dynamic value,
    ThqAccountingColumn column,
    String currency,
  ) {
    if (value == null) return '—';
    if (column.type == 'money') {
      return '$currency ${(value as num).toStringAsFixed(2)}';
    }
    return value.toString();
  }

  static List<List<dynamic>> journalLines(ThqAccountingResult result) => [
    [
      'Date',
      'Reference',
      'Journal number',
      'Source',
      'Status',
      'Account',
      'Debit',
      'Credit',
    ],
    for (final row in result.rows)
      for (final line in accountingMaps(row['lines']))
        [
          row['date'],
          row['reference'],
          row['entry_number'],
          row['source_type'],
          row['status'],
          line['account_name'],
          line['debit'],
          line['credit'],
        ],
  ];
  Future<void> export(
    ThqAccountingQuery query,
    String format,
    String business,
    String currency,
  ) async {
    final data = await all(query);
    final title = thqAccountingSections[query.report] ?? query.report;
    final name =
        'THQ_${query.report}_${query.from.toIso8601String().substring(0, 10)}_${query.to.toIso8601String().substring(0, 10)}';
    final scope = locationId == null ? 'Permitted stores' : 'Selected store';
    final metadata = [
      business,
      title,
      '${query.from.toIso8601String().substring(0, 10)} to ${query.to.toIso8601String().substring(0, 10)}',
      '$scope · $currency',
      'Search: ${query.search}',
      'Filters: ${query.filters}',
      'Balance basis: ${data.context['balance_basis'] ?? ''}',
      'Generated: ${data.context['generated_at'] ?? ''}',
    ];
    if (format == 'xlsx') {
      final book = Excel.createExcel();
      book.rename('Sheet1', 'Report');
      final sheet = book['Report'];
      for (final text in metadata) {
        sheet.appendRow([TextCellValue(text)]);
      }
      sheet.appendRow(data.columns.map((c) => TextCellValue(c.label)).toList());
      for (final row in data.rows) {
        sheet.appendRow(
          data.columns.map<CellValue>((c) {
            final value = row[c.key];
            return value is num
                ? DoubleCellValue(value.toDouble())
                : TextCellValue(value?.toString() ?? '');
          }).toList(),
        );
      }
      final totals = book['Totals'];
      totals.appendRow([TextCellValue('Metric'), TextCellValue('Amount')]);
      for (final metric in data.summary) {
        totals.appendRow([
          TextCellValue(metric['label']?.toString() ?? ''),
          DoubleCellValue((metric['value'] as num? ?? 0).toDouble()),
        ]);
      }
      if (query.report == 'journal') {
        final lines = book['Journal Lines'];
        for (final row in journalLines(data)) {
          lines.appendRow(
            row
                .map<CellValue>(
                  (v) => v is num
                      ? DoubleCellValue(v.toDouble())
                      : TextCellValue(v?.toString() ?? ''),
                )
                .toList(),
          );
        }
      }
      final saved = book.save();
      if (saved == null) {
        throw StateError('Unable to build accounting workbook.');
      }
      await FileSaver.instance.saveFile(
        name: name,
        bytes: Uint8List.fromList(saved),
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      return;
    }
    final bytes = await buildPdf(query, data, business, currency);
    if (format == 'print') {
      await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
    } else {
      await FileSaver.instance.saveFile(
        name: name,
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
    }
  }

  Future<Uint8List> buildPdf(
    ThqAccountingQuery query,
    ThqAccountingResult data,
    String business,
    String currency,
  ) async {
    final title = thqAccountingSections[query.report] ?? query.report;
    final metadata = [
      business,
      title,
      '${query.from.toIso8601String().substring(0, 10)} to ${query.to.toIso8601String().substring(0, 10)}',
      '${data.context['location'] ?? 'Selected scope'} · $currency',
      'Search: ${query.search}',
      'Filters: ${query.filters}',
      'Balance basis: ${data.context['balance_basis'] ?? ''}',
      'Generated: ${data.context['generated_at'] ?? ''}',
    ];
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/report_fonts/ReportSans.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/report_fonts/ReportSans-Bold.ttf'),
    );
    final fallback = [
      pw.Font.ttf(
        await rootBundle.load('assets/report_fonts/NotoSansMalayalam.ttf'),
      ),
      pw.Font.ttf(
        await rootBundle.load('assets/report_fonts/NotoSansDevanagari.ttf'),
      ),
    ];
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        fontFallback: fallback,
      ),
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        maxPages: 10000,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => pw.Text(
          '$business · $title',
          style: pw.TextStyle(font: bold, fontSize: 12),
        ),
        footer: (context) => pw.Text(
          '${context.pageNumber} / ${context.pagesCount} · $currency',
          style: const pw.TextStyle(fontSize: 8),
        ),
        build: (_) => [
          for (final line in metadata.skip(2))
            pw.Text(line, style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: data.columns.map((c) => c.label).toList(),
            data: [
              for (final row in data.rows)
                [
                  for (final c in data.columns)
                    display(row[c.key], c, currency),
                ],
            ],
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle: pw.TextStyle(font: bold, fontSize: 8),
          ),
          pw.SizedBox(height: 10),
          for (final metric in data.summary)
            pw.Text(
              '${metric['label']}: $currency ${(metric['value'] as num? ?? 0).toStringAsFixed(2)}',
            ),
          if (query.report == 'journal') ...[
            pw.SizedBox(height: 12),
            pw.Text('Complete journal lines', style: pw.TextStyle(font: bold)),
            pw.TableHelper.fromTextArray(
              headers: journalLines(data).first,
              data: journalLines(data)
                  .skip(1)
                  .map(
                    (r) => r
                        .map(
                          (x) => x is num
                              ? x.toStringAsFixed(2)
                              : x?.toString() ?? '',
                        )
                        .toList(),
                  )
                  .toList(),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerStyle: pw.TextStyle(font: bold, fontSize: 8),
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }
}
