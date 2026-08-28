import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as print_pkg;
import 'package:printing_ffi/printing_ffi.dart' as ffi;

class PosHardwareService {
  Future<List<String>> listPrinters() async {
    final names = <String>{};
    try {
      final printers = await print_pkg.Printing.listPrinters();
      for (final printer in printers) {
        if (printer.name.trim().isNotEmpty) names.add(printer.name.trim());
      }
    } catch (_) {}
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        for (final printer in ffi.PrintingFfi.instance.listPrinters()) {
          if (printer.name.trim().isNotEmpty) names.add(printer.name.trim());
        }
      } catch (_) {}
    }
    final rows = names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return rows;
  }

  Future<void> directPrintPdfBytes({
    required String printerName,
    required Uint8List bytes,
    String jobName = 'THQ POS',
  }) async {
    final printers = await print_pkg.Printing.listPrinters();
    final target = printers
        .where(
          (p) =>
              p.name.trim().toLowerCase() == printerName.trim().toLowerCase(),
        )
        .firstOrNull;
    if (target == null) {
      throw Exception('Printer "$printerName" is not currently available.');
    }
    final ok = await print_pkg.Printing.directPrintPdf(
      printer: target,
      name: jobName,
      onLayout: (_) async => bytes,
    );
    if (!ok) throw Exception('Printer did not accept the job.');
  }

  Future<void> testPrint(
    String printerName, {
    String paperSize = '80mm',
  }) async {
    final narrow = paperSize == '58mm' || paperSize == '80mm';
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: narrow
            ? PdfPageFormat(
                80 * PdfPageFormat.mm,
                120 * PdfPageFormat.mm,
                marginAll: 5 * PdfPageFormat.mm,
              )
            : PdfPageFormat.a4,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'THQ POS V4.6',
              style: pw.TextStyle(
                fontSize: narrow ? 15 : 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Printer test successful'),
            pw.Text(
              'Printer: $printerName',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              'Paper profile: $paperSize',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'If this is aligned correctly, select this printer as the default invoice or KOT route.',
            ),
          ],
        ),
      ),
    );
    await directPrintPdfBytes(
      printerName: printerName,
      bytes: await doc.save(),
      jobName: 'THQ POS Printer Test',
    );
  }

  Future<void> printKot({
    required List<Map<String, dynamic>> profiles,
    required String orderNumber,
    required String orderType,
    String? tableName,
    int? prepMinutes,
    String? chefNote,
    required List<Map<String, dynamic>> items,
  }) async {
    if (profiles.isEmpty) return;
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          180 * PdfPageFormat.mm,
          marginAll: 4 * PdfPageFormat.mm,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                'KITCHEN ORDER',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Order: $orderNumber',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('Type: ${orderType.replaceAll('_', ' ').toUpperCase()}'),
            if (tableName != null && tableName.isNotEmpty)
              pw.Text('Table: $tableName'),
            if (prepMinutes != null) pw.Text('Prep: $prepMinutes min'),
            pw.Divider(),
            ...items.map(
              (item) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  children: [
                    pw.SizedBox(
                      width: 28,
                      child: pw.Text(
                        '${item['quantity'] ?? 1} x',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        item['name']?.toString() ??
                            item['product_name']?.toString() ??
                            'Item',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (chefNote != null && chefNote.trim().isNotEmpty) ...[
              pw.Divider(),
              pw.Text(
                'CHEF NOTE',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(chefNote.trim()),
            ],
            pw.Divider(),
            pw.Text(
              DateTime.now().toString().substring(0, 19),
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ),
    );
    final bytes = await doc.save();
    for (final profile in profiles) {
      final printerName = profile['printer_name']?.toString().trim() ?? '';
      if (printerName.isEmpty || profile['active'] == false) continue;
      final copies = ((profile['copies'] as num?)?.toInt() ?? 1).clamp(1, 10);
      for (var i = 0; i < copies; i++) {
        await directPrintPdfBytes(
          printerName: printerName,
          bytes: bytes,
          jobName: 'KOT $orderNumber',
        );
      }
    }
  }

  Future<void> openCashDrawer({
    required String printerName,
    String command = 'standard',
  }) async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      throw UnsupportedError(
        'Direct ESC/POS cash-drawer pulse is supported by THQ POS desktop. On Android, use the printer/vendor drawer interface.',
      );
    }
    final bytes = Uint8List.fromList(_drawerCommand(command));
    final ok = await ffi.PrintingFfi.instance.rawDataToPrinter(
      printerName,
      bytes,
      docName: 'THQ POS Cash Drawer',
    );
    if (!ok) {
      throw Exception(
        'Cash drawer pulse failed. Check printer name and drawer cable.',
      );
    }
  }

  List<int> _drawerCommand(String command) {
    final value = command.trim().toLowerCase();
    if (value == 'drawer2' || value == 'pin5') {
      return const [0x1B, 0x70, 0x01, 0x19, 0xFA];
    }
    if (value.startsWith('hex:')) {
      final out = <int>[];
      for (final part in value.substring(4).trim().split(RegExp(r'\s+'))) {
        final parsed = int.tryParse(part, radix: 16);
        if (parsed != null && parsed >= 0 && parsed <= 255) out.add(parsed);
      }
      if (out.isNotEmpty) return out;
    }
    return const [0x1B, 0x70, 0x00, 0x19, 0xFA];
  }
}
