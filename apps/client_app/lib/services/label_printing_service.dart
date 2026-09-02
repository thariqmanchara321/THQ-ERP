import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ProductLabelData {
  final String businessName;
  final String productName;
  final String sku;
  final String code;
  final String codeMode;
  final String priceText;

  const ProductLabelData({
    required this.businessName,
    required this.productName,
    required this.sku,
    required this.code,
    required this.codeMode,
    required this.priceText,
  });
}

class LabelPrintingService {
  Future<void> printLabels({
    required Map<String, dynamic> template,
    required ProductLabelData label,
    int copies = 1,
  }) async {
    final count = copies.clamp(1, 500);
    final widthMm = _number(template['width_mm'], 50);
    final heightMm = _number(template['height_mm'], 30);
    final columns = (_int(template['columns'], 1)).clamp(1, 6);
    final paperMode = template['paper_mode']?.toString() ?? 'thermal';
    final document = pw.Document();

    if (paperMode == 'a4') {
      final rows = <pw.Widget>[];
      for (var start = 0; start < count; start += columns) {
        final cells = <pw.Widget>[];
        for (var c = 0; c < columns; c++) {
          final index = start + c;
          cells.add(
            pw.Expanded(
              child: index < count
                  ? pw.Container(
                      margin: const pw.EdgeInsets.all(3),
                      height: heightMm * PdfPageFormat.mm,
                      child: _labelWidget(template, label),
                    )
                  : pw.SizedBox(),
            ),
          );
        }
        rows.add(pw.Row(children: cells));
      }
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(18),
          build: (_) => rows,
        ),
      );
    } else {
      final format = PdfPageFormat(
        widthMm * PdfPageFormat.mm,
        heightMm * PdfPageFormat.mm,
        marginAll: 2 * PdfPageFormat.mm,
      );
      for (var i = 0; i < count; i++) {
        document.addPage(
          pw.Page(
            pageFormat: format,
            build: (_) => _labelWidget(template, label),
          ),
        );
      }
    }

    await Printing.layoutPdf(
      name: '${label.sku.isEmpty ? 'THQ' : label.sku}_labels.pdf',
      onLayout: (_) => document.save(),
    );
  }

  pw.Widget _labelWidget(
    Map<String, dynamic> template,
    ProductLabelData label,
  ) {
    final showBusiness = template['show_business'] != false;
    final showProduct = template['show_product'] != false;
    final showPrice = template['show_price'] != false;
    final showSku = template['show_sku'] != false;
    final showCodeText = template['show_code_text'] != false;
    final mode = template['code_mode']?.toString() ?? label.codeMode;
    final qr = mode == 'qr';

    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: .5)),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (showBusiness && label.businessName.isNotEmpty)
            pw.Text(
              label.businessName,
              maxLines: 1,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            ),
          if (showProduct) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              label.productName,
              maxLines: 2,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
          ],
          pw.SizedBox(height: 3),
          pw.Expanded(
            child: pw.Center(
              child: pw.BarcodeWidget(
                barcode: qr ? pw.Barcode.qrCode() : pw.Barcode.code128(),
                data: label.code,
                drawText: false,
              ),
            ),
          ),
          if (showCodeText)
            pw.Text(
              label.code,
              maxLines: 1,
              style: const pw.TextStyle(fontSize: 6),
            ),
          if (showSku && label.sku.isNotEmpty)
            pw.Text(
              'SKU ${label.sku}',
              maxLines: 1,
              style: const pw.TextStyle(fontSize: 6),
            ),
          if (showPrice && label.priceText.isNotEmpty)
            pw.Text(
              label.priceText,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
        ],
      ),
    );
  }

  double _number(dynamic value, double fallback) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;
  int _int(dynamic value, int fallback) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
}
