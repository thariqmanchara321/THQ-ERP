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
    final name = await showDialog<String>(
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

    final scope = await showDialog<Map<String, String?>>(
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
    final accent = TextEditingController(
      text: '${draft['accent'] ?? '#5B5BD6'}',
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

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          void refresh([String? _]) => setLocal(() {});
          return AlertDialog(
            title: Text('Design • ${row['template_name']}'),
            content: SizedBox(
              width: 920,
              height: 620,
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${row['paper_type'].toString().toUpperCase()} • Design settings are stored as data so future THQ versions keep the layout.',
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _toggle(
                                'Logo',
                                showLogo,
                                (value) => setLocal(() => showLogo = value),
                              ),
                              _toggle(
                                'GSTIN',
                                showGstin,
                                (value) => setLocal(() => showGstin = value),
                              ),
                              _toggle(
                                'Phone',
                                showPhone,
                                (value) => setLocal(() => showPhone = value),
                              ),
                              _toggle(
                                'Email',
                                showEmail,
                                (value) => setLocal(() => showEmail = value),
                              ),
                              _toggle(
                                'Website',
                                showWebsite,
                                (value) => setLocal(() => showWebsite = value),
                              ),
                              _toggle(
                                'Address',
                                showAddress,
                                (value) => setLocal(() => showAddress = value),
                              ),
                              _toggle(
                                'Customer',
                                showCustomer,
                                (value) => setLocal(() => showCustomer = value),
                              ),
                              _toggle(
                                'HSN/SAC',
                                showHsn,
                                (value) => setLocal(() => showHsn = value),
                              ),
                              _toggle(
                                'GST breakup',
                                showTax,
                                (value) => setLocal(() => showTax = value),
                              ),
                              _toggle(
                                'Header',
                                showHeader,
                                (value) => setLocal(() => showHeader = value),
                              ),
                              _toggle(
                                'Footer',
                                showFooter,
                                (value) => setLocal(() => showFooter = value),
                              ),
                              _toggle(
                                'Terms',
                                showTerms,
                                (value) => setLocal(() => showTerms = value),
                              ),
                              _toggle(
                                'Bank details',
                                showBank,
                                (value) => setLocal(() => showBank = value),
                              ),
                              _toggle(
                                'Payment / UPI',
                                showPayment,
                                (value) => setLocal(() => showPayment = value),
                              ),
                              _toggle(
                                'Payment QR',
                                showPaymentQr,
                                (value) =>
                                    setLocal(() => showPaymentQr = value),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: accent,
                                  onChanged: refresh,
                                  decoration: const InputDecoration(
                                    labelText: 'Accent / hex color',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: alignment,
                                  decoration: const InputDecoration(
                                    labelText: 'Header alignment',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'left',
                                      child: Text('Left'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'center',
                                      child: Text('Center'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'right',
                                      child: Text('Right'),
                                    ),
                                  ],
                                  onChanged: (value) => setLocal(
                                    () => alignment = value ?? 'center',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: font,
                                  onChanged: refresh,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Base font size',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: margin,
                                  onChanged: refresh,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Margin (mm)',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Invoice columns',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Select the columns that should appear on the printed/PDF invoice.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 5,
                            children: availableColumns
                                .map(
                                  (entry) => FilterChip(
                                    label: Text(entry.$2),
                                    selected: selectedColumns.contains(
                                      entry.$1,
                                    ),
                                    onSelected: (value) => setLocal(() {
                                      if (value) {
                                        selectedColumns.add(entry.$1);
                                      } else if (selectedColumns.length > 1) {
                                        selectedColumns.remove(entry.$1);
                                      }
                                    }),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: footer,
                            onChanged: refresh,
                            minLines: 2,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Template-specific footer',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _livePreview(row, currentConfig())),
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
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Duplicate'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Save & Set Default'),
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
    footer.dispose();
    font.dispose();
    margin.dispose();
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> change) =>
      FilterChip(
        label: Text(label),
        selected: value,
        onSelected: change,
        visualDensity: VisualDensity.compact,
      );

  Widget _livePreview(Map<String, dynamic> row, Map<String, dynamic> config) {
    final narrow = row['paper_type'] == '80mm';
    final headerAlignment = '${config['header_alignment'] ?? 'center'}';
    final align = switch (headerAlignment) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.center,
    };
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      padding: const EdgeInsets.all(12),
      child: Center(
        child: AspectRatio(
          aspectRatio: narrow ? 0.42 : 0.72,
          child: Container(
            padding: EdgeInsets.all(narrow ? 10 : 18),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black12),
              boxShadow: const [
                BoxShadow(blurRadius: 10, color: Colors.black12),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (config['show_logo'] != false)
                  SizedBox(
                    height: narrow ? 34 : 46,
                    child: _logoUrl.text.trim().isEmpty
                        ? const Icon(Icons.business, size: 28)
                        : Image.network(
                            _logoUrl.text.trim(),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.broken_image_outlined,
                                  size: 28,
                                ),
                          ),
                  ),
                if (config['show_header'] != false) ...[
                  if (_header.text.isNotEmpty)
                    Text(
                      _header.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: align,
                      style: const TextStyle(fontSize: 7),
                    ),
                  Text(
                    _legalName.text.isEmpty
                        ? widget.session.business.name
                        : _legalName.text,
                    textAlign: align,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: narrow ? 12 : 17,
                    ),
                  ),
                ],
                if (config['show_gstin'] != false && _gstin.text.isNotEmpty)
                  Text(
                    'GSTIN ${_gstin.text}',
                    textAlign: align,
                    style: const TextStyle(fontSize: 8),
                  ),
                if (config['show_phone'] != false && _phone.text.isNotEmpty)
                  Text(
                    'Phone: ${_phone.text}',
                    textAlign: align,
                    style: const TextStyle(fontSize: 8),
                  ),
                if (config['show_email'] == true && _email.text.isNotEmpty)
                  Text(
                    'Email: ${_email.text}',
                    textAlign: align,
                    style: const TextStyle(fontSize: 8),
                  ),
                if (config['show_website'] == true && _website.text.isNotEmpty)
                  Text(
                    _website.text,
                    textAlign: align,
                    style: const TextStyle(fontSize: 8),
                  ),
                if (config['show_address'] != false && _address.text.isNotEmpty)
                  Text(
                    _address.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: align,
                    style: const TextStyle(fontSize: 8),
                  ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Invoice # INV-00042',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (config['show_customer'] != false)
                      const Text(
                        'Customer: Walk-in',
                        style: TextStyle(fontSize: 8),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 5,
                    horizontal: 3,
                  ),
                  color: Colors.black.withValues(alpha: .04),
                  child: const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Item',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        'Qty  Rate  Total',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                ...List.generate(
                  3,
                  (index) => Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 5,
                      horizontal: 3,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Sample Product ${index + 1}',
                            style: const TextStyle(fontSize: 8),
                          ),
                        ),
                        Text(
                          '${index + 1}   120   ${(index + 1) * 120}',
                          style: const TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                const Divider(),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Grand Total   ₹720.00',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10),
                  ),
                ),
                if (config['show_bank_details'] == true &&
                    _bank.text.isNotEmpty)
                  Text(
                    'Bank: ${_bank.text}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 7),
                  ),
                if (config['show_payment_details'] != false &&
                    _payment.text.isNotEmpty)
                  Text(
                    _payment.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 7),
                  ),
                if (config['show_payment_qr'] == true &&
                    _paymentQrUrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _paymentQrLabel.text.trim().isEmpty
                        ? 'Scan to Pay'
                        : _paymentQrLabel.text.trim(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Align(
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: narrow ? 40 : 50,
                      height: narrow ? 40 : 50,
                      child: Image.network(
                        _paymentQrUrl.text.trim(),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.qr_code_2_outlined, size: 34),
                      ),
                    ),
                  ),
                ],
                if (config['show_terms'] != false && _terms.text.isNotEmpty)
                  Text(
                    _terms.text,
                    maxLines: narrow ? 3 : 5,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 7),
                  ),
                if (config['show_footer'] != false) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${config['footer'] ?? _footer.text}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 7),
                  ),
                ],
              ],
            ),
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
