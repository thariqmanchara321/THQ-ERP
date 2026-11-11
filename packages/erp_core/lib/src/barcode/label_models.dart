import 'barcode_format.dart';

/// Print media output mode.
enum PaperMode {
  thermal('Thermal Roll', 'Single continuous roll labels for thermal barcode printers (TSC, Zebra, TVS, Citizen)'),
  a4('A4 Sheet', 'Standard A4 multi-label sheets with rows and columns for laser and inkjet printers');

  final String label;
  final String description;

  const PaperMode(this.label, this.description);

  static PaperMode fromCode(String code) {
    return code.trim().toLowerCase() == 'a4' ? PaperMode.a4 : PaperMode.thermal;
  }
}

/// Physical label dimensions and margin specifications.
class LabelDimensions {
  final double widthMm;
  final double heightMm;
  final double marginMm;
  final int columns;
  final int rows;

  const LabelDimensions({
    required this.widthMm,
    required this.heightMm,
    this.marginMm = 2.0,
    this.columns = 1,
    this.rows = 1,
  });

  // Standard retail & warehouse presets
  static const thermal50x25 = LabelDimensions(
    widthMm: 50.0,
    heightMm: 25.0,
    marginMm: 1.5,
  );

  static const thermal50x30 = LabelDimensions(
    widthMm: 50.0,
    heightMm: 30.0,
    marginMm: 2.0,
  );

  static const thermal58x40 = LabelDimensions(
    widthMm: 58.0,
    heightMm: 40.0,
    marginMm: 2.0,
  );

  static const thermal100x50 = LabelDimensions(
    widthMm: 100.0,
    heightMm: 50.0,
    marginMm: 3.0,
  );

  static const a4_3x8_24 = LabelDimensions(
    widthMm: 70.0,
    heightMm: 37.0,
    marginMm: 2.0,
    columns: 3,
    rows: 8,
  );

  static const a4_2x7_14 = LabelDimensions(
    widthMm: 105.0,
    heightMm: 42.0,
    marginMm: 2.0,
    columns: 2,
    rows: 7,
  );

  static const a4_4x10_40 = LabelDimensions(
    widthMm: 52.5,
    heightMm: 29.7,
    marginMm: 1.5,
    columns: 4,
    rows: 10,
  );
}

/// Reusable label layout and visibility configuration.
class LabelTemplate {
  final String? id;
  final String code;
  final String name;
  final PaperMode paperMode;
  final double widthMm;
  final double heightMm;
  final int columns;
  final int rows;
  final bool showBusiness;
  final bool showProduct;
  final bool showPrice;
  final bool showSku;
  final bool showCodeText;
  final bool showBrand;
  final LabelBarcodeFormat barcodeFormat;
  final bool isDefault;
  final bool systemTemplate;
  final bool active;

  const LabelTemplate({
    this.id,
    required this.code,
    required this.name,
    this.paperMode = PaperMode.thermal,
    required this.widthMm,
    required this.heightMm,
    this.columns = 1,
    this.rows = 1,
    this.showBusiness = true,
    this.showProduct = true,
    this.showPrice = true,
    this.showSku = true,
    this.showCodeText = true,
    this.showBrand = false,
    this.barcodeFormat = LabelBarcodeFormat.code128,
    this.isDefault = false,
    this.systemTemplate = false,
    this.active = true,
  });

  factory LabelTemplate.fromMap(Map<String, dynamic> map) {
    final modeStr = map['code_mode']?.toString() ?? 'code128';
    return LabelTemplate(
      id: map['id']?.toString(),
      code: map['code']?.toString() ?? 'CUSTOM',
      name: map['name']?.toString() ?? 'Custom Label',
      paperMode: PaperMode.fromCode(map['paper_mode']?.toString() ?? 'thermal'),
      widthMm: (map['width_mm'] as num?)?.toDouble() ?? 50.0,
      heightMm: (map['height_mm'] as num?)?.toDouble() ?? 30.0,
      columns: ((map['columns'] as num?)?.toInt() ?? 1).clamp(1, 6),
      rows: (map['rows'] as num?)?.toInt() ?? 1,
      showBusiness: map['show_business'] != false,
      showProduct: map['show_product'] != false,
      showPrice: map['show_price'] != false,
      showSku: map['show_sku'] != false,
      showCodeText: map['show_code_text'] != false,
      showBrand: map['show_brand'] == true,
      barcodeFormat: LabelBarcodeFormat.fromCode(modeStr),
      isDefault: map['is_default'] == true,
      systemTemplate: map['system_template'] == true,
      active: map['active'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'code': code,
        'name': name,
        'paper_mode': paperMode == PaperMode.a4 ? 'a4' : 'thermal',
        'width_mm': widthMm,
        'height_mm': heightMm,
        'columns': columns,
        'rows': rows,
        'show_business': showBusiness,
        'show_product': showProduct,
        'show_price': showPrice,
        'show_sku': showSku,
        'show_code_text': showCodeText,
        'show_brand': showBrand,
        'code_mode': barcodeFormat.name,
        'is_default': isDefault,
        'system_template': systemTemplate,
        'active': active,
      };

  LabelTemplate copyWith({
    String? id,
    String? code,
    String? name,
    PaperMode? paperMode,
    double? widthMm,
    double? heightMm,
    int? columns,
    int? rows,
    bool? showBusiness,
    bool? showProduct,
    bool? showPrice,
    bool? showSku,
    bool? showCodeText,
    bool? showBrand,
    LabelBarcodeFormat? barcodeFormat,
    bool? isDefault,
    bool? systemTemplate,
    bool? active,
  }) {
    return LabelTemplate(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      paperMode: paperMode ?? this.paperMode,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
      showBusiness: showBusiness ?? this.showBusiness,
      showProduct: showProduct ?? this.showProduct,
      showPrice: showPrice ?? this.showPrice,
      showSku: showSku ?? this.showSku,
      showCodeText: showCodeText ?? this.showCodeText,
      showBrand: showBrand ?? this.showBrand,
      barcodeFormat: barcodeFormat ?? this.barcodeFormat,
      isDefault: isDefault ?? this.isDefault,
      systemTemplate: systemTemplate ?? this.systemTemplate,
      active: active ?? this.active,
    );
  }

  // Pre-configured built-in templates
  static const standardThermal = LabelTemplate(
    code: 'THERMAL_50X30',
    name: 'Standard Thermal (50 x 30 mm)',
    paperMode: PaperMode.thermal,
    widthMm: 50.0,
    heightMm: 30.0,
    columns: 1,
    showBusiness: true,
    showProduct: true,
    showPrice: true,
    showSku: true,
    showCodeText: true,
    barcodeFormat: LabelBarcodeFormat.code128,
    isDefault: true,
    systemTemplate: true,
  );

  static const compactThermal = LabelTemplate(
    code: 'THERMAL_50X25',
    name: 'Compact Tag (50 x 25 mm)',
    paperMode: PaperMode.thermal,
    widthMm: 50.0,
    heightMm: 25.0,
    columns: 1,
    showBusiness: false,
    showProduct: true,
    showPrice: true,
    showSku: true,
    showCodeText: true,
    barcodeFormat: LabelBarcodeFormat.code128,
    isDefault: false,
    systemTemplate: true,
  );

  static const shippingThermal = LabelTemplate(
    code: 'THERMAL_58X40',
    name: 'Shipping / Box Label (58 x 40 mm)',
    paperMode: PaperMode.thermal,
    widthMm: 58.0,
    heightMm: 40.0,
    columns: 1,
    showBusiness: true,
    showProduct: true,
    showPrice: true,
    showSku: true,
    showCodeText: true,
    showBrand: true,
    barcodeFormat: LabelBarcodeFormat.code128,
    isDefault: false,
    systemTemplate: true,
  );

  static const a4Sheet24 = LabelTemplate(
    code: 'A4_3X8',
    name: 'A4 Sheet — 24 Labels (70 x 37 mm)',
    paperMode: PaperMode.a4,
    widthMm: 70.0,
    heightMm: 37.0,
    columns: 3,
    rows: 8,
    showBusiness: true,
    showProduct: true,
    showPrice: true,
    showSku: true,
    showCodeText: true,
    barcodeFormat: LabelBarcodeFormat.code128,
    isDefault: false,
    systemTemplate: true,
  );

  static const a4Sheet14 = LabelTemplate(
    code: 'A4_2X7',
    name: 'A4 Sheet — 14 Labels (105 x 42 mm)',
    paperMode: PaperMode.a4,
    widthMm: 105.0,
    heightMm: 42.0,
    columns: 2,
    rows: 7,
    showBusiness: true,
    showProduct: true,
    showPrice: true,
    showSku: true,
    showCodeText: true,
    showBrand: true,
    barcodeFormat: LabelBarcodeFormat.code128,
    isDefault: false,
    systemTemplate: true,
  );

  static const a4Sheet40 = LabelTemplate(
    code: 'A4_4X10',
    name: 'A4 Sheet — 40 Micro Tags (52.5 x 29.7 mm)',
    paperMode: PaperMode.a4,
    widthMm: 52.5,
    heightMm: 29.7,
    columns: 4,
    rows: 10,
    showBusiness: false,
    showProduct: true,
    showPrice: true,
    showSku: true,
    showCodeText: true,
    barcodeFormat: LabelBarcodeFormat.code128,
    isDefault: false,
    systemTemplate: true,
  );

  static List<LabelTemplate> get standardPresets => [
        standardThermal,
        compactThermal,
        shippingThermal,
        a4Sheet24,
        a4Sheet14,
        a4Sheet40,
      ];
}

/// An individual item queued for label printing.
class LabelPrintItem {
  final String productId;
  final String variantId;
  final String productName;
  final String? variantName;
  final String? brandName;
  final String sku;
  final String code;
  final LabelBarcodeFormat format;
  final double sellingPrice;
  final String currencyCode;
  final int copies;

  const LabelPrintItem({
    required this.productId,
    required this.variantId,
    required this.productName,
    this.variantName,
    this.brandName,
    required this.sku,
    required this.code,
    this.format = LabelBarcodeFormat.code128,
    required this.sellingPrice,
    this.currencyCode = 'INR',
    this.copies = 1,
  });

  String get priceText => currencyCode == 'INR'
      ? 'Rs. ${sellingPrice.toStringAsFixed(2)}'
      : '$currencyCode ${sellingPrice.toStringAsFixed(2)}';

  LabelPrintItem copyWith({
    String? productId,
    String? variantId,
    String? productName,
    String? variantName,
    String? brandName,
    String? sku,
    String? code,
    LabelBarcodeFormat? format,
    double? sellingPrice,
    String? currencyCode,
    int? copies,
  }) {
    return LabelPrintItem(
      productId: productId ?? this.productId,
      variantId: variantId ?? this.variantId,
      productName: productName ?? this.productName,
      variantName: variantName ?? this.variantName,
      brandName: brandName ?? this.brandName,
      sku: sku ?? this.sku,
      code: code ?? this.code,
      format: format ?? this.format,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      currencyCode: currencyCode ?? this.currencyCode,
      copies: copies ?? this.copies,
    );
  }
}

