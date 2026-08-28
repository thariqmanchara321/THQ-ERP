import 'package:flutter/material.dart';
import '../services/platform_config_service.dart';

class TenantInvoiceTemplatesScreen extends StatefulWidget {
  final String tenantId, businessName;
  const TenantInvoiceTemplatesScreen({
    super.key,
    required this.tenantId,
    required this.businessName,
  });
  @override
  State<TenantInvoiceTemplatesScreen> createState() =>
      _TenantInvoiceTemplatesScreenState();
}

class _TenantInvoiceTemplatesScreenState
    extends State<TenantInvoiceTemplatesScreen> {
  final _s = PlatformConfigService();
  late Future<List<Map<String, dynamic>>> _f;
  String? _a4, _thermal;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _f = _s.getInvoiceTemplates();
  }

  Future<void> _save() async {
    if (_a4 == null || _thermal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select both A4 and 80mm templates.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _s.setTenantInvoiceTemplate(
        tenantId: widget.tenantId,
        paperType: 'a4',
        templateId: _a4!,
      );
      await _s.setTenantInvoiceTemplate(
        tenantId: widget.tenantId,
        paperType: '80mm',
        templateId: _thermal!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice templates assigned.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FA),
    appBar: AppBar(title: Text('${widget.businessName} • Invoice Designs')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) return Center(child: Text(s.error.toString()));
        final rows = s.data ?? [];
        final a4 = rows.where((e) => e['paper_type'] == 'a4').toList();
        final th = rows.where((e) => e['paper_type'] == '80mm').toList();
        _a4 ??= a4.isEmpty ? null : a4.first['id']?.toString();
        _thermal ??= th.isEmpty ? null : th.first['id']?.toString();
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: SizedBox(
              width: 760,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Invoice Template Assignment',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Choose the default A4 invoice and 80mm counter receipt for this business.',
                      ),
                      const SizedBox(height: 22),
                      DropdownButtonFormField<String>(
                        initialValue: _a4,
                        decoration: const InputDecoration(
                          labelText: 'A4 Invoice',
                        ),
                        items: a4
                            .map(
                              (x) => DropdownMenuItem(
                                value: x['id']?.toString(),
                                child: Text(x['name']?.toString() ?? ''),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _a4 = v),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _thermal,
                        decoration: const InputDecoration(
                          labelText: '80mm Thermal Receipt',
                        ),
                        items: th
                            .map(
                              (x) => DropdownMenuItem(
                                value: x['id']?.toString(),
                                child: Text(x['name']?.toString() ?? ''),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _thermal = v),
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Saving...' : 'Save Templates'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
