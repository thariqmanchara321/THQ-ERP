import 'package:flutter/material.dart';
import '../widgets/admin_home_button.dart';

import '../services/platform_config_service.dart';

class InvoiceTemplatesScreen extends StatefulWidget {
  const InvoiceTemplatesScreen({super.key});

  @override
  State<InvoiceTemplatesScreen> createState() => _InvoiceTemplatesScreenState();
}

class _InvoiceTemplatesScreenState extends State<InvoiceTemplatesScreen> {
  final PlatformConfigService _service = PlatformConfigService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _service.getInvoiceTemplates();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final config = row?['config'] is Map
        ? Map<String, dynamic>.from(row!['config'] as Map)
        : <String, dynamic>{};

    final key = TextEditingController(text: row?['key']?.toString() ?? '');
    final name = TextEditingController(text: row?['name']?.toString() ?? '');
    final description = TextEditingController(
      text: row?['description']?.toString() ?? '',
    );
    final footer = TextEditingController(
      text: config['footer']?.toString() ?? 'Thank you for your business',
    );

    var paper = row?['paper_type']?.toString() ?? 'a4';
    var sampleLogo = row?['sample_logo_key']?.toString() ?? 'flexi_mark';
    var active = row?['is_active'] != false;
    var showLogo = config['show_logo'] != false;
    var showGstin = config['show_gstin'] != false;
    var showPhone = config['show_phone'] != false;
    var showAddress = config['show_address'] != false;
    var showTaxBreakup = config['show_tax_breakup'] != false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            row == null ? 'New Invoice Template' : 'Edit Invoice Template',
          ),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: key,
                    decoration: const InputDecoration(
                      labelText: 'Template Key',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Template Name',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: paper,
                    items: const [
                      DropdownMenuItem(value: 'a4', child: Text('A4 Invoice')),
                      DropdownMenuItem(
                        value: '80mm',
                        child: Text('80mm Thermal Receipt'),
                      ),
                    ],
                    onChanged: (value) {
                      setDialogState(() => paper = value ?? 'a4');
                    },
                    decoration: const InputDecoration(labelText: 'Paper Type'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: sampleLogo,
                    items: const [
                      DropdownMenuItem(
                        value: 'flexi_mark',
                        child: Text('Sample Logo — THQ Mark'),
                      ),
                      DropdownMenuItem(
                        value: 'flexi_store',
                        child: Text('Sample Logo — THQ Store'),
                      ),
                      DropdownMenuItem(
                        value: '',
                        child: Text('No sample logo'),
                      ),
                    ],
                    onChanged: (value) {
                      setDialogState(() => sampleLogo = value ?? '');
                    },
                    decoration: const InputDecoration(labelText: 'Sample Logo'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: footer,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Footer Text'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      FilterChip(
                        selected: showLogo,
                        label: const Text('Logo'),
                        onSelected: (value) {
                          setDialogState(() => showLogo = value);
                        },
                      ),
                      FilterChip(
                        selected: showGstin,
                        label: const Text('GSTIN'),
                        onSelected: (value) {
                          setDialogState(() => showGstin = value);
                        },
                      ),
                      FilterChip(
                        selected: showPhone,
                        label: const Text('Phone'),
                        onSelected: (value) {
                          setDialogState(() => showPhone = value);
                        },
                      ),
                      FilterChip(
                        selected: showAddress,
                        label: const Text('Address'),
                        onSelected: (value) {
                          setDialogState(() => showAddress = value);
                        },
                      ),
                      FilterChip(
                        selected: showTaxBreakup,
                        label: const Text('Tax Breakup'),
                        onSelected: (value) {
                          setDialogState(() => showTaxBreakup = value);
                        },
                      ),
                    ],
                  ),
                  SwitchListTile(
                    value: active,
                    onChanged: (value) {
                      setDialogState(() => active = value);
                    },
                    title: const Text('Active'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      await _service.saveInvoiceTemplate(
        id: row?['id']?.toString(),
        key: key.text,
        name: name.text,
        paperType: paper,
        description: description.text,
        config: {
          'show_logo': showLogo,
          'show_gstin': showGstin,
          'show_phone': showPhone,
          'show_address': showAddress,
          'show_tax_breakup': showTaxBreakup,
          'footer': footer.text,
        },
        sampleLogoKey: sampleLogo,
        isActive: active,
      );
      if (mounted) {
        await _refresh();
      }
    }

    key.dispose();
    name.dispose();
    description.dispose();
    footer.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Invoice Templates'),
        actions: const [AdminHomeButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('New Template'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }

          final rows = snapshot.data ?? const [];
          return ListView(
            padding: const EdgeInsets.all(28),
            children: [
              const Text(
                'Invoice Designer',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              const Text(
                'Manage reusable A4 and 80mm GST invoice designs, visible '
                'fields, sample logos and footer text. Businesses can be '
                'assigned different A4 and thermal templates.',
              ),
              const SizedBox(height: 20),
              ...rows.map(
                (item) => Card(
                  child: ListTile(
                    leading: Icon(
                      item['paper_type'] == '80mm'
                          ? Icons.receipt_long
                          : Icons.description_outlined,
                    ),
                    title: Text(item['name']?.toString() ?? ''),
                    subtitle: Text(
                      '${item['paper_type']?.toString().toUpperCase()} • '
                      '${item['key']} • '
                      '${item['sample_logo_key'] ?? 'No logo'}',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _edit(item),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
