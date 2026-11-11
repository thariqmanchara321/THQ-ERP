import 'dart:typed_data';

import 'package:erp_core/erp_core.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Legacy label data model preserved for backward compatibility with [ProductIdentifiersScreen].
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

  LabelPrintItem toPrintItem({int copies = 1}) {
    return LabelPrintItem(
      productId: '',
      variantId: '',
      productName: productName,
      sku: sku,
      code: code,
      format: LabelBarcodeFormat.fromCode(codeMode),
      sellingPrice: 0.0,
      copies: copies,
    );
  }
}

/// Professional label generation and printing service supporting both single labels
/// and multi-product batches across Thermal roll printers and A4 multi-label sheets.
class LabelPrintingService {
  const LabelPrintingService();

  // ---------------------------------------------------------------------------
  // Modern Multi-Item Batch Printing API (Phase 8)
  // ---------------------------------------------------------------------------

  /// Compiles a [pw.Document] containing barcode labels for the provided items and template.
  pw.Document buildPdfDocument({
    required LabelTemplate template,
    required List<LabelPrintItem> items,
    required String businessName,
  }) {
    final document = pw.Document();

    if (template.paperMode == PaperMode.a4) {
      _buildA4Pages(document, template, items, businessName);
    } else {
      _buildThermalPages(document, template, items, businessName);
    }

    return document;
  }

  /// Generates the raw PDF bytes for printing or file export.
  Future<Uint8List> generatePdfBytes({
    required LabelTemplate template,
    required List<LabelPrintItem> items,
    required String businessName,
  }) {
    final doc = buildPdfDocument(
      template: template,
      items: items,
      businessName: businessName,
    );
    return doc.save();
  }

  /// Sends the generated labels to the platform printing dialog.
  Future<void> printBatchLabels({
    required LabelTemplate template,
    required List<LabelPrintItem> items,
    required String businessName,
    String? jobName,
  }) async {
    final bytes = await generatePdfBytes(
      template: template,
      items: items,
      businessName: businessName,
    );

    final safeJobName = (jobName != null && jobName.isNotEmpty)
        ? jobName
        : 'THQ_Barcode_Labels_${DateTime.now().millisecondsSinceEpoch}';

    await Printing.layoutPdf(
      name: '$safeJobName.pdf',
      onLayout: (_) async => bytes,
    );
  }

  // ---------------------------------------------------------------------------
  // Backward Compatible API (ProductIdentifiersScreen)
  // ---------------------------------------------------------------------------

  /// Legacy print entry point preserved for backward compatibility.
  Future<void> printLabels({
    required Map<String, dynamic> template,
    required ProductLabelData label,
    int copies = 1,
  }) async {
    final labelTemplate = LabelTemplate.fromMap(template);
    final printItem = LabelPrintItem(
      productId: '',
      variantId: '',
      productName: label.productName,
      sku: label.sku,
      code: label.code,
      format: LabelBarcodeFormat.fromCode(label.codeMode),
      sellingPrice: 0.0,
      copies: copies.clamp(1, 500),
    );

    await printBatchLabels(
      template: labelTemplate,
      items: [printItem],
      businessName: label.businessName,
      jobName: label.sku.isEmpty ? 'THQ_Label' : label.sku,
    );
  }

  // ---------------------------------------------------------------------------
  // Internal PDF Page Builders
  // ---------------------------------------------------------------------------

  void _buildThermalPages(
    pw.Document doc,
    LabelTemplate template,
    List<LabelPrintItem> items,
    String businessName,
  ) {
    final format = PdfPageFormat(
      template.widthMm * PdfPageFormat.mm,
      template.heightMm * PdfPageFormat.mm,
      marginAll: 1.5 * PdfPageFormat.mm,
    );

    for (final item in items) {
      final count = item.copies.clamp(1, 500);
      for (var i = 0; i < count; i++) {
        doc.addPage(
          pw.Page(
            pageFormat: format,
            build: (_) => _buildLabelCell(template, item, businessName, isA4: false),
          ),
        );
      }
    }
  }

  void _buildA4Pages(
    pw.Document doc,
    LabelTemplate template,
    List<LabelPrintItem> items,
    String businessName,
  ) {
    final flatLabels = <LabelPrintItem>[];
    for (final item in items) {
      final count = item.copies.clamp(1, 500);
      for (var i = 0; i < count; i++) {
        flatLabels.add(item);
      }
    }

    if (flatLabels.isEmpty) return;

    final columns = template.columns.clamp(1, 6);
    final rowsList = <pw.Widget>[];

    for (var start = 0; start < flatLabels.length; start += columns) {
      final cells = <pw.Widget>[];
      for (var c = 0; c < columns; c++) {
        final index = start + c;
        if (index < flatLabels.length) {
          final item = flatLabels[index];
          cells.add(
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.all(1.5),
                height: template.heightMm * PdfPageFormat.mm,
                child: _buildLabelCell(template, item, businessName, isA4: true),
              ),
            ),
          );
        } else {
          cells.add(pw.Expanded(child: pw.SizedBox()));
        }
      }
      rowsList.add(pw.Row(children: cells));
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 10 * PdfPageFormat.mm, vertical: 10 * PdfPageFormat.mm),
        build: (_) => rowsList,
      ),
    );
  }

  pw.Widget _buildLabelCell(
    LabelTemplate template,
    LabelPrintItem item,
    String businessName, {
    required bool isA4,
  }) {
    final effectiveFormat = template.barcodeFormat != LabelBarcodeFormat.code128
        ? template.barcodeFormat
        : item.format;

    final barcodeWidget = _createBarcodeWidget(effectiveFormat, item.code);

    return pw.Container(
      padding: const pw.EdgeInsets.all(3.0),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.5, color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(2),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Store / Business Name
          if (template.showBusiness && businessName.isNotEmpty)
            pw.Text(
              businessName,
              maxLines: 1,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: isA4 ? 7.5 : 6.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),

          // Brand / Variant Name
          if (template.showBrand && ((item.brandName?.isNotEmpty ?? false) || (item.variantName?.isNotEmpty ?? false)))
            pw.Text(
              [item.brandName, item.variantName].whereType<String>().where((s) => s.isNotEmpty).join(' • '),
              maxLines: 1,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 5.5, color: PdfColors.grey700),
            ),

          // Product Name
          if (template.showProduct && item.productName.isNotEmpty) ...[
            pw.SizedBox(height: 1),
            pw.Text(
              item.productName,
              maxLines: 2,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: isA4 ? 8.5 : 7.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],

          pw.SizedBox(height: 2),

          // Vector Barcode Widget
          pw.Expanded(
            child: pw.Center(
              child: barcodeWidget,
            ),
          ),

          // Human Readable Barcode Number
          if (template.showCodeText && item.code.isNotEmpty)
            pw.Text(
              item.code,
              maxLines: 1,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: isA4 ? 6.5 : 5.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),

          // SKU & Price Footer
          if (template.showSku || template.showPrice) ...[
            pw.SizedBox(height: 1),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (template.showSku && item.sku.isNotEmpty)
                  pw.Text(
                    'SKU: ${item.sku}',
                    maxLines: 1,
                    style: pw.TextStyle(fontSize: 6.0, color: PdfColors.grey800),
                  )
                else
                  pw.SizedBox(),
                if (template.showPrice && item.sellingPrice > 0)
                  pw.Text(
                    item.priceText,
                    style: pw.TextStyle(
                      fontSize: isA4 ? 9.0 : 8.0,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _createBarcodeWidget(LabelBarcodeFormat format, String code) {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) {
      return pw.Text('NO CODE', style: const pw.TextStyle(fontSize: 6));
    }

    try {
      switch (format) {
        case LabelBarcodeFormat.ean13:
          if (BarcodeValidator.isValidEan13(cleanCode)) {
            return pw.BarcodeWidget(
              barcode: pw.Barcode.ean13(),
              data: cleanCode,
              drawText: false,
            );
          }
          // Fallback to Code 128 if not exact 13 digits
          return pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: cleanCode,
            drawText: false,
          );

        case LabelBarcodeFormat.upcA:
          if (BarcodeValidator.isValidUpcA(cleanCode)) {
            return pw.BarcodeWidget(
              barcode: pw.Barcode.upcA(),
              data: cleanCode,
              drawText: false,
            );
          }
          return pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: cleanCode,
            drawText: false,
          );

        case LabelBarcodeFormat.qrCode:
          return pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: cleanCode,
            drawText: false,
          );

        case LabelBarcodeFormat.code128:
          return pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: cleanCode,
            drawText: false,
          );
      }
    } catch (_) {
      // Safe fallback on any low-level pdf encoding failure
      return pw.BarcodeWidget(
        barcode: pw.Barcode.code128(),
        data: cleanCode,
        drawText: false,
      );
    }
  }
}
