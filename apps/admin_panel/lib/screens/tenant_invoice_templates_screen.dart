import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
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
      ThqNotify.showSnackBar(
        context,
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
        ThqNotify.showSnackBar(
          context,
          const SnackBar(content: Text('Invoice templates assigned.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: Text(
          '${widget.businessName} | Invoice Designs',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _f,
        builder: (context, s) {
          if (s.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (s.hasError) {
            return Center(child: Text(s.error.toString()));
          }

          final rows = s.data ?? [];
          final a4 = rows.where((e) => e['paper_type'] == 'a4').toList();
          final thermal = rows.where((e) => e['paper_type'] == '80mm').toList();

          _a4 ??= a4.isEmpty ? null : a4.first['id']?.toString();
          _thermal ??= thermal.isEmpty ? null : thermal.first['id']?.toString();

          return Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 25,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Invoice Template Assignment',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Default A4 invoice and 80mm receipt',
                              style: TextStyle(fontSize: 7.7),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 14),
                        label: Text(_saving ? 'Saving...' : 'Save Templates'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked = constraints.maxWidth < 760;

                      Widget selector({
                        required String title,
                        required String subtitle,
                        required IconData icon,
                        required String? value,
                        required List<Map<String, dynamic>> templates,
                        required ValueChanged<String?> onChanged,
                      }) {
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(icon, size: 17, color: scheme.primary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 7.5,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                initialValue: value,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Template',
                                ),
                                items: templates
                                    .map(
                                      (x) => DropdownMenuItem(
                                        value: x['id']?.toString(),
                                        child: Text(
                                          x['name']?.toString() ?? '',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: onChanged,
                              ),
                            ],
                          ),
                        );
                      }

                      final a4Panel = selector(
                        title: 'A4 Invoice',
                        subtitle: '${a4.length} template(s) available',
                        icon: Icons.description_outlined,
                        value: _a4,
                        templates: a4,
                        onChanged: (v) => setState(() => _a4 = v),
                      );

                      final thermalPanel = selector(
                        title: '80mm Thermal Receipt',
                        subtitle: '${thermal.length} template(s) available',
                        icon: Icons.receipt_long_outlined,
                        value: _thermal,
                        templates: thermal,
                        onChanged: (v) => setState(() => _thermal = v),
                      );

                      if (stacked) {
                        return Column(
                          children: [
                            Expanded(child: a4Panel),
                            const SizedBox(height: 5),
                            Expanded(child: thermalPanel),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: a4Panel),
                          const SizedBox(width: 5),
                          Expanded(child: thermalPanel),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
