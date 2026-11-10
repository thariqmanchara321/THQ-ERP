import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../services/invoice_template_service.dart';
import '../services/location_scope_service.dart';
import '../services/location_service.dart';
import '../services/tenant_settings_service.dart';

class InvoiceDesignerScreen extends StatefulWidget {
  final ClientSession session;

  const InvoiceDesignerScreen({super.key, required this.session});

  @override
  State<InvoiceDesignerScreen> createState() => _InvoiceDesignerScreenState();
}

class _InvoiceDesignerScreenState extends State<InvoiceDesignerScreen>
    with SingleTickerProviderStateMixin {
  final InvoiceTemplateService _templates = InvoiceTemplateService();
  final TenantSettingsService _settingsService = TenantSettingsService();

  late final TabController _tabs;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingLogo = false;
  bool _uploadingPaymentQr = false;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  Map<String, dynamic> _settings = {};

  final _legalName = TextEditingController();
  final _gstin = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _address = TextEditingController();
  final _logoUrl = TextEditingController();
  final _header = TextEditingController();
  final _footer = TextEditingController();
  final _terms = TextEditingController();
  final _bank = TextEditingController();
  final _payment = TextEditingController();
  final _paymentQrUrl = TextEditingController();
  final _paymentQrLabel = TextEditingController();

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('settings.manage');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _legalName,
      _gstin,
      _phone,
      _email,
      _website,
      _address,
      _logoUrl,
      _header,
      _footer,
      _terms,
      _bank,
      _payment,
      _paymentQrUrl,
      _paymentQrLabel,
    ]) {
      controller.dispose();
    }
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _templates.listTemplates(tenantId: widget.session.business.id),
        _settingsService.getSettings(widget.session.business.id),
      ]);
      _rows = values[0] as List<Map<String, dynamic>>;
      _settings = values[1] as Map<String, dynamic>;

      String value(String key, [String fallback = '']) =>
          _settings[key]?.toString() ?? fallback;

      _legalName.text = value(
        'business.legal_name',
        widget.session.business.name,
      );
      _gstin.text = value('business.gstin');
      _phone.text = value('business.phone');
      _email.text = value('business.email');
      _website.text = value('business.website');
      _address.text = value('business.address');
      _logoUrl.text = value('business.logo_url');
      _header.text = value('documents.invoice_header');
      _footer.text = value('documents.invoice_footer');
      _terms.text = value('documents.terms');
      _bank.text = value('documents.bank_details');
      _payment.text = value('documents.payment_details');
      _paymentQrUrl.text = value('documents.payment_qr_url');
      _paymentQrLabel.text = value('documents.payment_qr_label', 'Scan to Pay');
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveIdentity() async {
    if (!_canManage || _saving) return;
    setState(() => _saving = true);
    try {
      final next = Map<String, dynamic>.from(_settings)
        ..['business.legal_name'] = _legalName.text.trim()
        ..['business.gstin'] = _gstin.text.trim()
        ..['business.phone'] = _phone.text.trim()
        ..['business.email'] = _email.text.trim()
        ..['business.website'] = _website.text.trim()
        ..['business.address'] = _address.text.trim()
        ..['business.logo_url'] = _logoUrl.text.trim()
        ..['documents.invoice_header'] = _header.text.trim()
        ..['documents.invoice_footer'] = _footer.text.trim()
        ..['documents.terms'] = _terms.text.trim()
        ..['documents.bank_details'] = _bank.text.trim()
        ..['documents.payment_details'] = _payment.text.trim()
        ..['documents.payment_qr_url'] = _paymentQrUrl.text.trim()
        ..['documents.payment_qr_label'] = _paymentQrLabel.text.trim();
      await _settingsService.setSettings(widget.session.business.id, next);
      _settings = next;
      _message('Invoice identity saved.');
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadLogo() async {
    if (!_canManage || _uploadingLogo) return;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Logo image', extensions: ['png', 'jpg', 'jpeg']),
      ],
    );
    if (file == null) return;
    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    if (!const {'png', 'jpg', 'jpeg'}.contains(extension)) {
      _message('Please choose a PNG or JPEG logo.');
      return;
    }
    setState(() => _uploadingLogo = true);
    try {
      final bytes = await file.readAsBytes();
      final url = await _templates.uploadBusinessLogo(
        tenantId: widget.session.business.id,
        bytes: bytes,
        extension: extension,
      );
      if (!mounted) return;
      setState(() => _logoUrl.text = url);
      _message('Logo uploaded. Save Identity to apply it.');
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _uploadPaymentQr() async {
    if (!_canManage || _uploadingPaymentQr) return;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Payment QR image',
          extensions: ['png', 'jpg', 'jpeg'],
        ),
      ],
    );
    if (file == null) return;
    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    if (!const {'png', 'jpg', 'jpeg'}.contains(extension)) {
      _message('Please choose a PNG or JPEG QR image.');
      return;
    }
    setState(() => _uploadingPaymentQr = true);
    try {
      final bytes = await file.readAsBytes();
      final url = await _templates.uploadPaymentQr(
        tenantId: widget.session.business.id,
        bytes: bytes,
        extension: extension,
      );
      if (!mounted) return;
      setState(() => _paymentQrUrl.text = url);
      _message('Payment QR uploaded. Save Identity to apply it.');
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _uploadingPaymentQr = false);
    }
  }

  Future<void> _duplicate(Map<String, dynamic> row) async {
    if (!_canManage) return;
    final controller = TextEditingController(
      text: '${row['template_name'] ?? 'Invoice'} Copy',
    );
    final name = await showThqDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create Custom Template'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Template name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    try {
      await _templates.duplicateTemplate(
        tenantId: widget.session.business.id,
        sourceTemplateId: row['template_id'].toString(),
        name: name,
        paperType: row['paper_type'].toString(),
        config: row['effective_config'] is Map
            ? Map<String, dynamic>.from(row['effective_config'] as Map)
            : null,
      );
      await _load();
      _message('Custom template created.');
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _assignToStore(Map<String, dynamic> row) async {
    if (!_canManage) return;
    final locations = LocationScopeService.writableLocations(widget.session);
    if (locations.isEmpty) {
      _message('No writable store is available.');
      return;
    }

    final directory = await LocationService().directory(
      widget.session.business.id,
    );
    if (!mounted) return;
    final devices = (directory['devices'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .where((device) => device['status']?.toString() != 'revoked')
        .toList();

    String selectedLocation =
        LocationScopeService.selectedLocationId.value ?? locations.first.id;
    if (!locations.any((location) => location.id == selectedLocation)) {
      selectedLocation = locations.first.id;
    }
    String? selectedDevice;

    final scope = await showThqDialog<Map<String, String?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          final terminalOptions = devices
              .where(
                (device) =>
                    device['location_id']?.toString() == selectedLocation,
              )
              .toList();
          if (selectedDevice != null &&
              !terminalOptions.any(
                (device) => device['id']?.toString() == selectedDevice,
              )) {
            selectedDevice = null;
          }
          return AlertDialog(
            title: const Text('Assign Invoice Template'),
            content: SizedBox(
              width: 470,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedLocation,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Store / location',
                    ),
                    items: locations
                        .map(
                          (location) => DropdownMenuItem(
                            value: location.id,
                            child: Text('${location.code} • ${location.name}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setLocal(() {
                          selectedLocation = value;
                          selectedDevice = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedDevice,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Terminal / Client system (optional)',
                      helperText:
                          'Leave empty to make this the store default. A terminal assignment overrides its store default.',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Store default • all systems'),
                      ),
                      ...terminalOptions.map(
                        (device) => DropdownMenuItem<String?>(
                          value: device['id']?.toString(),
                          child: Text(
                            '${device['device_code'] ?? ''} • ${device['name'] ?? ''}',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setLocal(() => selectedDevice = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, {
                  'location_id': selectedLocation,
                  'device_id': selectedDevice,
                }),
                child: const Text('Assign'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
    if (scope == null) return;

    try {
      await _templates.assignTemplate(
        tenantId: widget.session.business.id,
        paperType: row['paper_type'].toString(),
        templateId: row['template_id'].toString(),
        locationId: scope['location_id'],
        deviceId: scope['device_id'],
        overrides: row['effective_config'] is Map
            ? Map<String, dynamic>.from(row['effective_config'] as Map)
            : const {},
      );
      _message(
        scope['device_id'] == null
            ? 'Template assigned as the selected store default.'
            : 'Template assigned to the selected terminal/system.',
      );
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _customize(Map<String, dynamic> row) async {
    if (!_canManage) {
      _message('Owner or settings.manage permission required.');
      return;
    }

    final config = row['effective_config'] is Map
        ? Map<String, dynamic>.from(row['effective_config'] as Map)
        : <String, dynamic>{};
    final draft = Map<String, dynamic>.from(config);
    var documentType = (draft['document_type'] ?? '').toString().trim().toLowerCase();
    if (documentType != 'estimate' && documentType != 'tax_invoice') {
      final tName = (row['template_name'] ?? '').toString().toLowerCase();
      documentType = tName.contains('estimate') ? 'estimate' : 'tax_invoice';
    }
    final accent = TextEditingController(
      text: '${draft['accent'] ?? '#5B5BD6'}',
    );
    final companyName = TextEditingController(
      text: '${draft['company_name'] ?? ''}',
    );
    final companyColor = TextEditingController(
      text: '${draft['company_name_color'] ?? '#0F172A'}',
    );
    final companySize = TextEditingController(
      text: '${draft['company_name_size'] ?? '26'}',
    );
    final footer = TextEditingController(text: '${draft['footer'] ?? ''}');
    final font = TextEditingController(
      text: '${draft['font_size'] ?? (row['paper_type'] == '80mm' ? 8 : 10)}',
    );
    final margin = TextEditingController(
      text: '${draft['margin_mm'] ?? (row['paper_type'] == '80mm' ? 4 : 12)}',
    );
    const availableColumns = <(String, String)>[
      ('item', 'Item / Description'),
      ('sku', 'SKU / Code'),
      ('hsn', 'HSN / SAC'),
      ('qty', 'Quantity'),
      ('unit', 'Unit'),
      ('rate', 'Rate'),
      ('discount', 'Discount'),
      ('tax', 'Tax %'),
      ('tax_amount', 'Tax Amount'),
      ('taxable', 'Taxable Amount'),
      ('total', 'Line Total'),
    ];
    final selectedColumns = <String>{
      ...((draft['columns'] is List
              ? draft['columns'] as List
              : const [
                  'item',
                  'sku',
                  'hsn',
                  'qty',
                  'rate',
                  'discount',
                  'tax',
                  'total',
                ])
          .map((value) => value.toString().trim().toLowerCase())
          .where((value) => value.isNotEmpty)),
    };

    bool flag(String key, bool fallback) =>
        draft.containsKey(key) ? draft[key] == true : fallback;

    var companyBold = flag('company_name_bold', true);
    var companyItalic = flag('company_name_italic', false);
    var companyUpper = flag('company_name_uppercase', false);
    var showBranch = flag('show_branch_name', false);
    var showErpRef = flag('show_erp_ref', false);
    var showLogo = flag('show_logo', true);
    var showGstin = flag('show_gstin', true);
    var showPhone = flag('show_phone', true);
    var showEmail = flag('show_email', false);
    var showWebsite = flag('show_website', false);
    var showAddress = flag('show_address', true);
    var showHsn = flag('show_hsn', true);
    var showTax = flag('show_tax_breakup', true);
    var showCustomer = flag('show_customer', true);
    var showBank = flag('show_bank_details', false);
    var showPayment = flag('show_payment_details', true);
    var showPaymentQr = flag('show_payment_qr', false);
    var showTerms = flag('show_terms', true);
    var showHeader = flag('show_header', true);
    var showFooter = flag('show_footer', true);
    var alignment = '${draft['header_alignment'] ?? 'center'}';

    Map<String, dynamic> currentConfig() => {
      ...draft,
      'document_type': documentType,
      'company_name': companyName.text.trim(),
      'company_name_color': companyColor.text.trim(),
      'company_name_size': double.tryParse(companySize.text) ?? 26,
      'company_name_bold': companyBold,
      'company_name_italic': companyItalic,
      'company_name_uppercase': companyUpper,
      'show_branch_name': showBranch,
      'show_erp_ref': showErpRef,
      'show_logo': showLogo,
      'show_gstin': showGstin,
      'show_phone': showPhone,
      'show_email': showEmail,
      'show_website': showWebsite,
      'show_address': showAddress,
      'show_customer': showCustomer,
      'show_hsn': showHsn,
      'show_tax_breakup': showTax,
      'show_header': showHeader,
      'show_footer': showFooter,
      'show_terms': showTerms,
      'show_bank_details': showBank,
      'show_payment_details': showPayment,
      'show_payment_qr': showPaymentQr,
      'header_alignment': alignment,
      'accent': accent.text.trim(),
      'font_size': double.tryParse(font.text) ?? 10,
      'margin_mm': double.tryParse(margin.text) ?? 8,
      'footer': footer.text.trim(),
      'columns': availableColumns
          .where((entry) => selectedColumns.contains(entry.$1))
          .map((entry) => entry.$1)
          .toList(),
    };

    const colorSwatches = <(String, String, Color)>[
      ('indigo', 'Indigo', Color(0xFF4F46E5)),
      ('teal', 'Teal', Color(0xFF0D9488)),
      ('emerald', 'Emerald', Color(0xFF059669)),
      ('navy', 'Navy', Color(0xFF1E40AF)),
      ('slate', 'Slate', Color(0xFF334155)),
      ('crimson', 'Crimson', Color(0xFFBE123C)),
      ('amber', 'Amber', Color(0xFFD97706)),
      ('violet', 'Violet', Color(0xFF7C3AED)),
      ('dark', 'Dark', Color(0xFF0F172A)),
    ];

    final save = await showThqDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          void refresh([String? _]) => setLocal(() {});
          final currentAccent = _parseAccent(currentConfig());
          final currentAccentRaw = accent.text.trim().toLowerCase();
          final screenSize = MediaQuery.sizeOf(context);
          final dialogWidth = (screenSize.width - 48).clamp(820.0, 1180.0);
          final dialogHeight = (screenSize.height - 48).clamp(560.0, 780.0);

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            title: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: currentAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.palette_outlined, size: 20, color: currentAccent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Design • ${row['template_name']}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${row['paper_type'].toString().toUpperCase()} • Professional invoice styling & live layout engine',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: currentAccent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: currentAccent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    row['paper_type'].toString().toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: currentAccent,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: dialogWidth,
              height: dialogHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left side controls
                  Expanded(
                    flex: 5,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Document Type Selection (Tax Invoice vs Estimate)
                          const Text(
                            'Document Type',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'tax_invoice',
                                icon: Icon(Icons.receipt_long_outlined, size: 14),
                                label: Text('Tax Invoice', style: TextStyle(fontSize: 11)),
                              ),
                              ButtonSegment(
                                value: 'estimate',
                                icon: Icon(Icons.request_quote_outlined, size: 14),
                                label: Text('Estimate', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                            selected: {documentType},
                            onSelectionChanged: (val) => setLocal(() => documentType = val.first),
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 1. Accent Color Palette
                          const Text(
                            'Accent Theme Color',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: colorSwatches.map((swatch) {
                              final isActive = currentAccentRaw == swatch.$1 ||
                                  currentAccentRaw == '#${swatch.$3.toARGB32().toRadixString(16).substring(2).toLowerCase()}';
                              return InkWell(
                                onTap: () => setLocal(() => accent.text = swatch.$1),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isActive ? swatch.$3.withValues(alpha: 0.14) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isActive ? swatch.$3 : Colors.black12,
                                      width: isActive ? 1.6 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: swatch.$3,
                                          shape: BoxShape.circle,
                                        ),
                                        child: isActive
                                            ? const Icon(Icons.check, size: 9, color: Colors.white)
                                            : null,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        swatch.$2,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                          color: isActive ? swatch.$3 : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: TextField(
                                  controller: accent,
                                  onChanged: refresh,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: 'Custom Hex / Color Name',
                                    prefixIcon: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: currentAccent,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.black26),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 5,
                                child: SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'left',
                                      icon: Icon(Icons.format_align_left, size: 14),
                                      label: Text('Left', style: TextStyle(fontSize: 11)),
                                    ),
                                    ButtonSegment(
                                      value: 'center',
                                      icon: Icon(Icons.format_align_center, size: 14),
                                      label: Text('Center', style: TextStyle(fontSize: 11)),
                                    ),
                                    ButtonSegment(
                                      value: 'right',
                                      icon: Icon(Icons.format_align_right, size: 14),
                                      label: Text('Right', style: TextStyle(fontSize: 11)),
                                    ),
                                  ],
                                  selected: {alignment},
                                  onSelectionChanged: (val) => setLocal(() => alignment = val.first),
                                  style: const ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),
                          // Company Name & Header Styling
                          const Text(
                            'Company Name & Header Styling',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: companyName,
                            onChanged: refresh,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: 'Company / Display Name',
                              hintText: _legalName.text.isEmpty ? widget.session.business.name : _legalName.text,
                              prefixIcon: const Icon(Icons.business_outlined, size: 16),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: TextField(
                                  controller: companyColor,
                                  onChanged: refresh,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: 'Name Color (Hex or name)',
                                    prefixIcon: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: companyColor.text.trim().toLowerCase() == 'accent'
                                              ? currentAccent
                                              : _parseAccent({'accent': companyColor.text.trim().isEmpty ? '#0F172A' : companyColor.text.trim()}),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.black26),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 4,
                                child: TextField(
                                  controller: companySize,
                                  onChanged: refresh,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'Font Size (pt)',
                                    hintText: '26',
                                    prefixIcon: Icon(Icons.format_size, size: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                label: const Text('Match Accent', style: TextStyle(fontSize: 10)),
                                onPressed: () => setLocal(() => companyColor.text = 'accent'),
                              ),
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                label: const Text('Black', style: TextStyle(fontSize: 10)),
                                onPressed: () => setLocal(() => companyColor.text = '#0F172A'),
                              ),
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                label: const Text('Slate', style: TextStyle(fontSize: 10)),
                                onPressed: () => setLocal(() => companyColor.text = '#334155'),
                              ),
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                label: const Text('Navy', style: TextStyle(fontSize: 10)),
                                onPressed: () => setLocal(() => companyColor.text = '#1E40AF'),
                              ),
                              FilterChip(
                                visualDensity: VisualDensity.compact,
                                label: const Text('Bold', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                selected: companyBold,
                                onSelected: (v) => setLocal(() => companyBold = v),
                              ),
                              FilterChip(
                                visualDensity: VisualDensity.compact,
                                label: const Text('Italic', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
                                selected: companyItalic,
                                onSelected: (v) => setLocal(() => companyItalic = v),
                              ),
                              FilterChip(
                                visualDensity: VisualDensity.compact,
                                label: const Text('ALL CAPS', style: TextStyle(fontSize: 10)),
                                selected: companyUpper,
                                onSelected: (v) => setLocal(() => companyUpper = v),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),
                          // 2. Typography & Density
                          Row(
                            children: [
                              const Text(
                                'Density & Spacing',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                              const Spacer(),
                              Wrap(
                                spacing: 4,
                                children: [
                                  ActionChip(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    label: const Text('Compact', style: TextStyle(fontSize: 10)),
                                    onPressed: () => setLocal(() {
                                      font.text = '8.5';
                                      margin.text = '8.0';
                                    }),
                                  ),
                                  ActionChip(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    label: const Text('Standard', style: TextStyle(fontSize: 10)),
                                    onPressed: () => setLocal(() {
                                      font.text = '10.0';
                                      margin.text = '12.0';
                                    }),
                                  ),
                                  ActionChip(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    label: const Text('Spacious', style: TextStyle(fontSize: 10)),
                                    onPressed: () => setLocal(() {
                                      font.text = '11.5';
                                      margin.text = '16.0';
                                    }),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: font,
                                  onChanged: refresh,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'Font Size (pt)',
                                    prefixIcon: Icon(Icons.format_size, size: 16),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: margin,
                                  onChanged: refresh,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'Page Margin (mm)',
                                    prefixIcon: Icon(Icons.space_bar, size: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),
                          // 3. Columns & Presets
                          Row(
                            children: [
                              const Text(
                                'Invoice Columns',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                              const Spacer(),
                              Wrap(
                                spacing: 4,
                                children: [
                                  ActionChip(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    label: const Text('Retail', style: TextStyle(fontSize: 10)),
                                    onPressed: () => setLocal(() {
                                      selectedColumns
                                        ..clear()
                                        ..addAll(['item', 'qty', 'rate', 'total']);
                                    }),
                                  ),
                                  ActionChip(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    label: const Text('Standard', style: TextStyle(fontSize: 10)),
                                    onPressed: () => setLocal(() {
                                      selectedColumns
                                        ..clear()
                                        ..addAll(['item', 'qty', 'unit', 'rate', 'discount', 'total']);
                                    }),
                                  ),
                                  ActionChip(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    label: const Text('Full B2B GST', style: TextStyle(fontSize: 10)),
                                    onPressed: () => setLocal(() {
                                      selectedColumns
                                        ..clear()
                                        ..addAll([
                                          'item',
                                          'hsn',
                                          'qty',
                                          'unit',
                                          'rate',
                                          'discount',
                                          'tax',
                                          'taxable',
                                          'total',
                                        ]);
                                      showHsn = true;
                                      showTax = true;
                                    }),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Click columns to include or exclude from the printed and PDF invoice.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: availableColumns.map((entry) {
                              final isSelected = selectedColumns.contains(entry.$1);
                              return FilterChip(
                                label: Text(entry.$2, style: const TextStyle(fontSize: 11)),
                                selected: isSelected,
                                onSelected: (value) => setLocal(() {
                                  if (value) {
                                    selectedColumns.add(entry.$1);
                                  } else if (selectedColumns.length > 1) {
                                    selectedColumns.remove(entry.$1);
                                  }
                                }),
                                visualDensity: VisualDensity.compact,
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 14),
                          // 4. Section Toggles
                          const Text(
                            'Branding & Header Elements',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _toggle('Logo', showLogo, (v) => setLocal(() => showLogo = v)),
                              _toggle('Store / Branch name', showBranch, (v) => setLocal(() => showBranch = v)),
                              _toggle('ERP / Internal Ref', showErpRef, (v) => setLocal(() => showErpRef = v)),
                              _toggle('Header Note', showHeader, (v) => setLocal(() => showHeader = v)),
                              _toggle('GSTIN', showGstin, (v) => setLocal(() => showGstin = v)),
                              _toggle('Phone', showPhone, (v) => setLocal(() => showPhone = v)),
                              _toggle('Email', showEmail, (v) => setLocal(() => showEmail = v)),
                              _toggle('Website', showWebsite, (v) => setLocal(() => showWebsite = v)),
                              _toggle('Address', showAddress, (v) => setLocal(() => showAddress = v)),
                            ],
                          ),

                          const SizedBox(height: 10),
                          const Text(
                            'Customer & Compliance Elements',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _toggle('Customer (Bill To)', showCustomer, (v) => setLocal(() => showCustomer = v)),
                              _toggle('HSN/SAC', showHsn, (v) => setLocal(() => showHsn = v)),
                              _toggle('GST breakup', showTax, (v) => setLocal(() => showTax = v)),
                            ],
                          ),

                          const SizedBox(height: 10),
                          const Text(
                            'Payment & Footer Elements',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _toggle('Bank details', showBank, (v) => setLocal(() => showBank = v)),
                              _toggle('Payment / UPI', showPayment, (v) => setLocal(() => showPayment = v)),
                              _toggle('Payment QR', showPaymentQr, (v) => setLocal(() => showPaymentQr = v)),
                              _toggle('Terms', showTerms, (v) => setLocal(() => showTerms = v)),
                              _toggle('Footer', showFooter, (v) => setLocal(() => showFooter = v)),
                            ],
                          ),

                          const SizedBox(height: 12),
                          TextField(
                            controller: footer,
                            onChanged: refresh,
                            minLines: 2,
                            maxLines: 3,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Template-specific footer note',
                              hintText: 'e.g. Thank you for your business. Visit us again!',
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),

                  const VerticalDivider(width: 1),
                  const SizedBox(width: 12),

                  // Right side live preview
                  Expanded(
                    flex: 6,
                    child: _livePreview(row, currentConfig()),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              OutlinedButton.icon(
                onPressed: () => _duplicate(row),
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Duplicate'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: currentAccent,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Save & Set Default'),
              ),
            ],
          );
        },
      ),
    );

    final saved = currentConfig();
    if (save == true) {
      try {
        if (row['is_custom'] == true) {
          await _templates.updateCustomTemplate(
            tenantId: widget.session.business.id,
            templateId: row['template_id'].toString(),
            name: row['template_name'].toString(),
            config: saved,
          );
        }
        await _templates.saveSelection(
          tenantId: widget.session.business.id,
          paperType: row['paper_type'].toString(),
          templateId: row['template_id'].toString(),
          overrides: saved,
        );
        await _load();
        _message('Invoice template saved and set as default.');
      } catch (error) {
        _message(error.toString());
      }
    }

    accent.dispose();
    companyName.dispose();
    companyColor.dispose();
    companySize.dispose();
    footer.dispose();
    font.dispose();
    margin.dispose();
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> change) =>
      FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: value,
        onSelected: change,
        visualDensity: VisualDensity.compact,
      );

  Color _parseAccent(Map<String, dynamic> config) {
    final raw = (config['accent'] ?? '#4F46E5').toString().trim().toLowerCase();
    switch (raw) {
      case 'indigo':
        return const Color(0xFF4F46E5);
      case 'teal':
        return const Color(0xFF0D9488);
      case 'emerald':
      case 'green':
        return const Color(0xFF059669);
      case 'navy':
      case 'blue':
        return const Color(0xFF1E40AF);
      case 'slate':
      case 'mono':
      case 'gray':
      case 'grey':
      case 'charcoal':
        return const Color(0xFF334155);
      case 'crimson':
      case 'red':
      case 'rose':
        return const Color(0xFFBE123C);
      case 'amber':
      case 'orange':
        return const Color(0xFFD97706);
      case 'violet':
      case 'purple':
        return const Color(0xFF7C3AED);
      case 'dark':
      case 'black':
        return const Color(0xFF0F172A);
    }
    final hex = raw.replaceAll('#', '');
    if (hex.length == 6) {
      final val = int.tryParse(hex, radix: 16);
      if (val != null) return Color(0xFF000000 | val);
    } else if (hex.length == 8) {
      final val = int.tryParse(hex, radix: 16);
      if (val != null) return Color(val);
    }
    return const Color(0xFF4F46E5);
  }

  List<String> _previewResolveColumns(Map<String, dynamic> config, bool narrow) {
    final raw = config['columns'];
    final defaults = narrow
        ? <String>['item', 'qty', 'rate', 'total']
        : <String>['item', 'qty', 'unit', 'rate', 'total'];
    final requested = raw is List
        ? raw.map((v) => v.toString().trim().toLowerCase()).where((v) => v.isNotEmpty).toList()
        : defaults;
    final allowed = <String>{
      'item', 'sku', 'hsn', 'hsn_sac', 'qty', 'quantity',
      'unit', 'rate', 'price', 'discount', 'tax', 'tax_amount',
      'taxable', 'total',
    };
    final clean = requested.where(allowed.contains).where((c) {
      if (config['show_hsn'] == false && (c == 'hsn' || c == 'hsn_sac')) {
        return false;
      }
      return true;
    }).toList();
    return clean.isEmpty ? defaults : clean;
  }

  String _previewColumnLabel(String column) => switch (column.toLowerCase()) {
    'item' => 'Description',
    'sku' => 'SKU',
    'hsn' || 'hsn_sac' => 'HSN/SAC',
    'qty' || 'quantity' => 'Qty',
    'unit' => 'Unit',
    'rate' || 'price' => 'Rate',
    'discount' => 'Disc.',
    'tax' => 'Tax %',
    'tax_amount' => 'Tax Amt',
    'taxable' => 'Taxable',
    _ => 'Amount',
  };

  bool _previewIsNumeric(String column) => switch (column.toLowerCase()) {
    'item' || 'sku' || 'hsn' || 'hsn_sac' => false,
    _ => true,
  };

  String _previewSampleValue(String column, int index) {
    final norm = column.toLowerCase();
    switch (norm) {
      case 'item':
        return switch (index) {
          0 => 'Premium Steel Bolt M8',
          1 => 'Industrial Lubricant 1L',
          _ => 'Heavy Duty Cable 5m',
        };
      case 'sku':
        return switch (index) {
          0 => 'BOLT-001',
          1 => 'LUB-100',
          _ => 'CBL-505',
        };
      case 'hsn' || 'hsn_sac':
        return switch (index) {
          0 => '7318',
          1 => '2710',
          _ => '8544',
        };
      case 'qty' || 'quantity':
        return switch (index) {
          0 => '10.00',
          1 => '2.00',
          _ => '1.00',
        };
      case 'unit':
        return switch (index) {
          0 => 'PCS',
          1 => 'LTR',
          _ => 'MTR',
        };
      case 'rate' || 'price':
        return switch (index) {
          0 => '₹45.00',
          1 => '₹350.00',
          _ => '₹250.00',
        };
      case 'discount':
        return switch (index) {
          0 => '₹5.00',
          1 => '₹20.00',
          _ => '₹0.00',
        };
      case 'tax':
        return '18.0%';
      case 'tax_amount':
        return switch (index) {
          0 => '₹72.00',
          1 => '₹122.40',
          _ => '₹45.00',
        };
      case 'taxable':
        return switch (index) {
          0 => '₹400.00',
          1 => '₹680.00',
          _ => '₹250.00',
        };
      default:
        return switch (index) {
          0 => '₹472.00',
          1 => '₹802.40',
          _ => '₹295.00',
        };
    }
  }

  Map<int, TableColumnWidth> _previewColumnWidths(List<String> cols) {
    final map = <int, TableColumnWidth>{};
    for (var i = 0; i < cols.length; i++) {
      final c = cols[i].toLowerCase();
      map[i] = switch (c) {
        'item' => const FlexColumnWidth(2.8),
        'sku' => const FlexColumnWidth(1.3),
        'hsn' || 'hsn_sac' => const FlexColumnWidth(1.2),
        'qty' || 'quantity' => const FlexColumnWidth(1.0),
        'unit' => const FlexColumnWidth(0.9),
        'rate' || 'price' => const FlexColumnWidth(1.2),
        'discount' => const FlexColumnWidth(1.1),
        'tax' => const FlexColumnWidth(1.0),
        'tax_amount' => const FlexColumnWidth(1.2),
        'taxable' => const FlexColumnWidth(1.3),
        _ => const FlexColumnWidth(1.3),
      };
    }
    return map;
  }

  Widget _livePreview(Map<String, dynamic> row, Map<String, dynamic> config) {
    final narrow = row['paper_type'] == '80mm';
    final headerAlignment = '${config['header_alignment'] ?? 'center'}';
    final align = switch (headerAlignment) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.center,
    };
    final accentColor = _parseAccent(config);
    final columns = _previewResolveColumns(config, narrow);
    final footerText = '${config['footer'] ?? _footer.text}'.trim();
    final customName = (config['company_name']?.toString().trim().isNotEmpty == true)
        ? config['company_name'].toString().trim()
        : (_legalName.text.isEmpty ? widget.session.business.name : _legalName.text);
    final displayName = config['company_name_uppercase'] == true
        ? customName.toUpperCase()
        : customName;
    final rawCompColor = (config['company_name_color'] ?? '').toString().trim();
    final compColor = rawCompColor.toLowerCase() == 'accent'
        ? accentColor
        : _parseAccent({'accent': rawCompColor.isEmpty ? '#0F172A' : rawCompColor});
    final double configuredSize = double.tryParse(config['company_name_size']?.toString() ?? '') ?? 26.0;
    final double previewSize = (configuredSize / 26.0) * (narrow ? 12.0 : 15.0);
    final bool isBold = config['company_name_bold'] != false;
    final bool isItalic = config['company_name_italic'] == true;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: narrow ? 340 : 540,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: accentColor.withValues(alpha: 0.22)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top accent line
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(narrow ? 10 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo
                      if (config['show_logo'] != false) ...[
                        Container(
                          height: narrow ? 32 : 44,
                          alignment: switch (headerAlignment) {
                            'left' => Alignment.centerLeft,
                            'right' => Alignment.centerRight,
                            _ => Alignment.center,
                          },
                          child: _logoUrl.text.trim().isEmpty
                              ? Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.business_outlined, size: 24, color: accentColor),
                                )
                              : Image.network(
                                  _logoUrl.text.trim(),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) =>
                                      Icon(Icons.business_outlined, size: 28, color: accentColor),
                                ),
                        ),
                        const SizedBox(height: 6),
                      ],

                      // Header & Company Identity
                      if (config['show_header'] != false && _header.text.isNotEmpty)
                        Text(
                          _header.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: align,
                          style: TextStyle(fontSize: 8, color: Colors.grey.shade600),
                        ),
                      Text(
                        displayName,
                        textAlign: align,
                        style: TextStyle(
                          fontWeight: isBold ? FontWeight.w900 : FontWeight.w500,
                          fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                          fontSize: previewSize,
                          color: compColor,
                        ),
                      ),
                      if (config['show_branch_name'] == true)
                        Text(
                          'Store / Branch Location',
                          textAlign: align,
                          style: TextStyle(fontSize: 8.5, color: Colors.grey.shade700),
                        ),
                      if (config['show_gstin'] != false && _gstin.text.isNotEmpty)
                        Text(
                          'GSTIN: ${_gstin.text}',
                          textAlign: align,
                          style: const TextStyle(fontSize: 8.5),
                        ),
                      if (config['show_phone'] != false && _phone.text.isNotEmpty)
                        Text(
                          'Phone: ${_phone.text}',
                          textAlign: align,
                          style: const TextStyle(fontSize: 8.5),
                        ),
                      if (config['show_email'] == true && _email.text.isNotEmpty)
                        Text(
                          'Email: ${_email.text}',
                          textAlign: align,
                          style: const TextStyle(fontSize: 8.5),
                        ),
                      if (config['show_website'] == true && _website.text.isNotEmpty)
                        Text(
                          _website.text,
                          textAlign: align,
                          style: const TextStyle(fontSize: 8.5),
                        ),
                      if (config['show_address'] != false && _address.text.isNotEmpty)
                        Text(
                          _address.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: align,
                          style: TextStyle(fontSize: 8.5, color: Colors.grey.shade700),
                        ),

                      const SizedBox(height: 6),
                      Divider(height: 1, color: accentColor.withValues(alpha: 0.25)),
                      const SizedBox(height: 6),

                      // Title & Invoice Meta
                      Text(
                        config['document_type'] == 'estimate' ? 'ESTIMATE' : 'TAX INVOICE',
                        textAlign: align,
                        style: TextStyle(
                          fontSize: narrow ? 11 : 13,
                          fontWeight: FontWeight.w900,
                          color: accentColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            config['document_type'] == 'estimate'
                                ? 'Estimate #: EST-00042'
                                : 'Invoice #: INV-00042',
                            style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Date: 12/10/2026',
                            style: TextStyle(fontSize: 8.5, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                      if (config['show_erp_ref'] == true)
                        Text(
                          'ERP Ref: SAL-000042',
                          style: TextStyle(fontSize: 7.5, color: Colors.grey.shade600),
                        ),

                      // Bill To Customer Card
                      if (config['show_customer'] != false) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: accentColor.withValues(alpha: 0.12)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BILL TO',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 8,
                                  color: accentColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Acme Enterprises / Walk-in Customer',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 8.5),
                              ),
                              const Text(
                                'Kerala, India • Phone: 9876543210',
                                style: TextStyle(fontSize: 8),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 8),

                      // Dynamic Table Columns
                      Table(
                        columnWidths: _previewColumnWidths(columns),
                        border: TableBorder.all(
                          color: accentColor.withValues(alpha: 0.20),
                          width: 0.8,
                        ),
                        children: [
                          // Header
                          TableRow(
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.10),
                            ),
                            children: [
                              for (final col in columns)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                                  child: Text(
                                    _previewColumnLabel(col),
                                    textAlign: _previewIsNumeric(col) ? TextAlign.right : TextAlign.left,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 7.5,
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          // Sample rows
                          for (var r = 0; r < 3; r++)
                            TableRow(
                              decoration: BoxDecoration(
                                color: r.isOdd ? Colors.black.withValues(alpha: 0.015) : Colors.white,
                              ),
                              children: [
                                for (final col in columns)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3.5),
                                    child: Text(
                                      _previewSampleValue(col, r),
                                      textAlign: _previewIsNumeric(col) ? TextAlign.right : TextAlign.left,
                                      style: const TextStyle(fontSize: 7.5),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),

                      // GST Rate Summary Breakup (if enabled)
                      if (config['show_tax_breakup'] != false && !narrow) ...[
                        const SizedBox(height: 8),
                        Text(
                          'TAX SUMMARY',
                          style: TextStyle(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w800,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Table(
                          border: TableBorder.all(
                            color: accentColor.withValues(alpha: 0.18),
                            width: 0.8,
                          ),
                          children: [
                            TableRow(
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.07),
                              ),
                              children: const [
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                                  child: Text('GST Rate', style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                                  child: Text('Taxable', textAlign: TextAlign.right, style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                                  child: Text('CGST', textAlign: TextAlign.right, style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                                  child: Text('SGST', textAlign: TextAlign.right, style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                                  child: Text('Total', textAlign: TextAlign.right, style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            TableRow(
                              children: const [
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
                                  child: Text('18.00%', style: TextStyle(fontSize: 7)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
                                  child: Text('₹1,330.00', textAlign: TextAlign.right, style: TextStyle(fontSize: 7)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
                                  child: Text('₹119.70', textAlign: TextAlign.right, style: TextStyle(fontSize: 7)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
                                  child: Text('₹119.70', textAlign: TextAlign.right, style: TextStyle(fontSize: 7)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
                                  child: Text('₹1,569.40', textAlign: TextAlign.right, style: TextStyle(fontSize: 7)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 8),

                      // Totals Summary Box
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: narrow ? double.infinity : 200,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: accentColor.withValues(alpha: 0.16)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: const [
                                  Text('Discount', style: TextStyle(fontSize: 7.5)),
                                  Text('₹25.00', style: TextStyle(fontSize: 7.5)),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: const [
                                  Text('Taxable Value', style: TextStyle(fontSize: 7.5)),
                                  Text('₹1,330.00', style: TextStyle(fontSize: 7.5)),
                                ],
                              ),
                              if (config['show_tax_breakup'] != false) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: const [
                                    Text('CGST (9%)', style: TextStyle(fontSize: 7.5)),
                                    Text('₹119.70', style: TextStyle(fontSize: 7.5)),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: const [
                                    Text('SGST (9%)', style: TextStyle(fontSize: 7.5)),
                                    Text('₹119.70', style: TextStyle(fontSize: 7.5)),
                                  ],
                                ),
                              ],
                              Divider(height: 6, color: accentColor.withValues(alpha: 0.2)),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    config['document_type'] == 'estimate' ? 'ESTIMATED TOTAL' : 'TOTAL',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 9,
                                      color: accentColor,
                                    ),
                                  ),
                                  Text(
                                    '₹1,569.40',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 9,
                                      color: accentColor,
                                    ),
                                  ),
                                ],
                              ),
                              if (config['document_type'] != 'estimate') ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: const [
                                    Text('Paid', style: TextStyle(fontSize: 7.5)),
                                    Text('₹1,569.40', style: TextStyle(fontSize: 7.5)),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: const [
                                    Text('Balance', style: TextStyle(fontSize: 7.5)),
                                    Text('₹0.00', style: TextStyle(fontSize: 7.5)),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Bank / UPI details / QR
                      if (config['show_bank_details'] == true && _bank.text.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Bank: ${_bank.text}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: align,
                          style: const TextStyle(fontSize: 7.5),
                        ),
                      ],
                      if (config['show_payment_details'] != false && _payment.text.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _payment.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: align,
                          style: const TextStyle(fontSize: 7.5),
                        ),
                      ],
                      if (config['show_payment_qr'] == true && _paymentQrUrl.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Center(
                          child: Column(
                            children: [
                              Text(
                                _paymentQrLabel.text.trim().isEmpty ? 'Scan to Pay' : _paymentQrLabel.text.trim(),
                                style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 3),
                              SizedBox(
                                width: 44,
                                height: 44,
                                child: Image.network(
                                  _paymentQrUrl.text.trim(),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) =>
                                      Icon(Icons.qr_code_2_outlined, size: 36, color: accentColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Terms
                      if (config['show_terms'] != false && _terms.text.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Terms: ${_terms.text}',
                          maxLines: narrow ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 7, color: Colors.grey.shade700),
                        ),
                      ],

                      // Footer
                      if (config['show_footer'] != false && footerText.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          footerText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _message(String text) {
    if (mounted) {
      ThqNotify.showSnackBar(context, SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Invoice Templates',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Business identity + customizable A4 and 80mm designs.',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: compact
                    ? ListView(
                        children: [
                          _identityCard(),
                          const SizedBox(height: 8),
                          SizedBox(height: 650, child: _templatesPanel()),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 330,
                            child: SingleChildScrollView(
                              child: _identityCard(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: _templatesPanel()),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _identityCard() => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Invoice identity',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _field(_legalName, 'Company / legal name', Icons.business_outlined),
          _field(_gstin, 'GSTIN', Icons.badge_outlined),
          Row(
            children: [
              Expanded(child: _field(_phone, 'Phone', Icons.phone_outlined)),
              const SizedBox(width: 6),
              Expanded(child: _field(_email, 'Email', Icons.email_outlined)),
            ],
          ),
          _field(_website, 'Website', Icons.language_outlined),
          _field(_address, 'Address', Icons.location_on_outlined, lines: 2),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 92),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  height: 72,
                  child: _logoUrl.text.trim().isEmpty
                      ? const Center(
                          child: Icon(Icons.image_outlined, size: 32),
                        )
                      : Image.network(
                          _logoUrl.text.trim(),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 32,
                                ),
                              ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Business logo',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Text(
                        'PNG / JPG / JPEG • max 5 MB • fitted inside a fixed box',
                        style: TextStyle(fontSize: 10),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        children: [
                          OutlinedButton.icon(
                            onPressed: !_canManage || _uploadingLogo
                                ? null
                                : _uploadLogo,
                            icon: _uploadingLogo
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.upload_outlined, size: 16),
                            label: Text(
                              _uploadingLogo ? 'Uploading…' : 'Upload',
                            ),
                          ),
                          if (_logoUrl.text.trim().isNotEmpty)
                            TextButton(
                              onPressed: !_canManage
                                  ? null
                                  : () => setState(() => _logoUrl.clear()),
                              child: const Text('Remove'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _field(
            _logoUrl,
            'Logo URL (advanced / optional)',
            Icons.link_outlined,
          ),
          _field(_header, 'Header text', Icons.vertical_align_top, lines: 2),
          _field(_footer, 'Footer text', Icons.vertical_align_bottom, lines: 2),
          _field(_terms, 'Terms & conditions', Icons.notes_outlined, lines: 2),
          _field(
            _bank,
            'Bank details',
            Icons.account_balance_outlined,
            lines: 2,
          ),
          _field(
            _payment,
            'Payment / UPI details',
            Icons.payments_outlined,
            lines: 2,
          ),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 118),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: _paymentQrUrl.text.trim().isEmpty
                      ? const Center(
                          child: Icon(Icons.qr_code_2_outlined, size: 46),
                        )
                      : Image.network(
                          _paymentQrUrl.text.trim(),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 36,
                                ),
                              ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Payment QR image (optional)',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Text(
                        'Static QR only for now • PNG / JPG / JPEG • max 5 MB',
                        style: TextStyle(fontSize: 10),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          OutlinedButton.icon(
                            onPressed: !_canManage || _uploadingPaymentQr
                                ? null
                                : _uploadPaymentQr,
                            icon: _uploadingPaymentQr
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.upload_outlined, size: 16),
                            label: Text(
                              _uploadingPaymentQr ? 'Uploading…' : 'Upload QR',
                            ),
                          ),
                          if (_paymentQrUrl.text.trim().isNotEmpty)
                            TextButton(
                              onPressed: !_canManage
                                  ? null
                                  : () => setState(() => _paymentQrUrl.clear()),
                              child: const Text('Remove'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _field(_paymentQrLabel, 'QR label', Icons.label_outline),
          _field(
            _paymentQrUrl,
            'Payment QR URL (advanced / optional)',
            Icons.link_outlined,
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: !_canManage || _saving ? null : _saveIdentity,
              icon: const Icon(Icons.save_outlined, size: 17),
              label: Text(_saving ? 'Saving…' : 'Save Identity'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: TextField(
      controller: controller,
      enabled: _canManage,
      minLines: lines,
      maxLines: lines,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        prefixIcon: Icon(icon, size: 17),
      ),
    ),
  );

  Widget _templatesPanel() => Card(
    margin: EdgeInsets.zero,
    child: Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'A4'),
            Tab(text: '80mm'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [_templateList('a4'), _templateList('80mm')],
          ),
        ),
      ],
    ),
  );

  Widget _templateList(String paper) {
    final rows = _rows.where((row) => row['paper_type'] == paper).toList();
    if (rows.isEmpty) return const Center(child: Text('No templates.'));

    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final row = rows[index];
        final selected = row['selected'] == true;
        final config = row['effective_config'] is Map
            ? Map<String, dynamic>.from(row['effective_config'] as Map)
            : <String, dynamic>{};

        return InkWell(
          onTap: () => _customize(row),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).dividerColor,
              ),
              borderRadius: BorderRadius.circular(10),
              color: selected
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .045)
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: paper == '80mm' ? 42 : 56,
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    paper.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${row['template_name']}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          _Tag(
                            (config['document_type'] == 'estimate' ||
                                    (row['template_name'] ?? '')
                                        .toString()
                                        .toLowerCase()
                                        .contains('estimate'))
                                ? 'ESTIMATE'
                                : 'TAX INVOICE',
                          ),
                          if (row['is_custom'] == true) const _Tag('CUSTOM'),
                          if (selected) const _Tag('DEFAULT'),
                        ],
                      ),
                      Text(
                        '${row['description'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Logo ${config['show_logo'] != false ? '✓' : '—'} • GST ${config['show_tax_breakup'] != false ? '✓' : '—'} • HSN ${config['show_hsn'] != false ? '✓' : '—'} • ${config['header_alignment'] ?? 'center'}',
                        style: const TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') _customize(row);
                    if (value == 'duplicate') _duplicate(row);
                    if (value == 'assign_store') _assignToStore(row);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('Customize / Set default'),
                    ),
                    PopupMenuItem(
                      value: 'duplicate',
                      child: Text('Duplicate as custom'),
                    ),
                    PopupMenuItem(
                      value: 'assign_store',
                      child: Text('Assign to store / terminal'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;

  const _Tag(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
}
