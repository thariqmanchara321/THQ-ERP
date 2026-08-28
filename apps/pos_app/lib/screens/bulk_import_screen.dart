import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/client_session.dart';
import '../services/bulk_import_service.dart';

class BulkImportScreen extends StatefulWidget {
  final ClientSession session;
  const BulkImportScreen({super.key, required this.session});
  @override
  State<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends State<BulkImportScreen> {
  final _controller = TextEditingController(
    text:
        'name,sku,item_type,category,brand,barcode,part_number,cost_price,selling_price,list_price,tax_rate,reorder_level,opening_stock\n',
  );
  final _service = BulkImportService();
  bool _saving = false;
  String? _result;
  List<Map<String, dynamic>> _parse() {
    final lines = const LineSplitter()
        .convert(_controller.text)
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) return [];
    final h = lines.first.split(',').map((e) => e.trim()).toList();
    return lines.skip(1).map((line) {
      final c = line.split(',');
      final m = <String, dynamic>{};
      for (var i = 0; i < h.length; i++) {
        m[h[i]] = i < c.length ? c[i].trim() : '';
      }
      return m;
    }).toList();
  }

  Future<void> _run() async {
    final rows = _parse();
    if (rows.isEmpty) {
      setState(() => _result = 'Add at least one product row.');
      return;
    }
    setState(() {
      _saving = true;
      _result = null;
    });
    try {
      final r = await _service.importProducts(
        tenantId: widget.session.business.id,
        rows: rows,
      );
      if (mounted) {
        setState(
          () => _result =
              'Imported ${r['success_count'] ?? 0}; failed ${r['failed_count'] ?? 0}. ${r['errors'] ?? ''}',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _result = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bulk Product Import',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Paste CSV rows. Keep commas out of text fields for this fast importer. Existing Inventory rules still create every product.',
        ),
        const SizedBox(height: 16),
        Expanded(
          child: TextField(
            controller: _controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
              labelText: 'CSV data',
            ),
          ),
        ),
        if (_result != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SelectableText(_result!),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _saving ? null : _run,
            icon: const Icon(Icons.upload_file),
            label: Text(_saving ? 'Importing...' : 'Import Products'),
          ),
        ),
      ],
    ),
  );
}
