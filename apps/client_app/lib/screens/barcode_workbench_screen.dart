import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../services/barcode_service.dart';
import '../services/location_scope_service.dart';

class BarcodeWorkbenchScreen extends StatefulWidget {
  final ClientSession session;
  const BarcodeWorkbenchScreen({super.key, required this.session});

  @override
  State<BarcodeWorkbenchScreen> createState() => _BarcodeWorkbenchScreenState();
}

class _BarcodeWorkbenchScreenState extends State<BarcodeWorkbenchScreen> {
  final BarcodeService _service = BarcodeService();
  final TextEditingController _barcode = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _loading = false;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _barcode.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = _barcode.text.trim();
    if (code.isEmpty || _loading) return;
    setState(() => _loading = true);
    try {
      final result = await _service.lookup(
        tenantId: widget.session.business.id,
        barcode: code,
        locationId: LocationScopeService.currentForRead(widget.session),
      );
      if (mounted) setState(() => _result = result.isEmpty ? null : result);
      if (result.isEmpty) _message('No product found for barcode $code.');
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _barcode.clear();
        _focus.requestFocus();
      }
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ThqNotify.showSnackBar(context, SnackBar(content: Text(text)));
  }

  String _money(dynamic value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse('$value') ?? 0;
    return widget.session.currencyCode == 'INR'
        ? '₹${number.toStringAsFixed(2)}'
        : '${widget.session.currencyCode} ${number.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final location = LocationScopeService.selectedLocation(widget.session);
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: EdgeInsets.all(constraints.maxWidth < 700 ? 12 : 20),
        child: ListView(
          children: [
            const Text(
              'Barcode Workbench',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              'USB/Bluetooth HID scanners work anywhere this field has focus. Scan a product to look it up instantly in ${location?.name ?? 'All Stores'}.',
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, inner) {
                    final field = TextField(
                      controller: _barcode,
                      focusNode: _focus,
                      autofocus: true,
                      onSubmitted: (_) => _scan(),
                      decoration: const InputDecoration(
                        labelText: 'Scan or enter barcode',
                        prefixIcon: Icon(Icons.qr_code_scanner),
                        hintText: 'Scanner sends barcode + Enter',
                      ),
                    );
                    final button = FilledButton.icon(
                      onPressed: _loading ? null : _scan,
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      label: const Text('Lookup'),
                    );
                    if (inner.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [field, const SizedBox(height: 8), button],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: field),
                        const SizedBox(width: 10),
                        button,
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_result != null) _resultCard(_result!),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Barcode workflow',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• Product forms store editable unique barcodes.\n• Sales/POS searches accept barcode, SKU and product name.\n• Purchase product search accepts barcode/SKU.\n• Scanner input behaves like a fast keyboard, so it works on Windows, Android tablets and Web without locking the app to one camera plugin.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(Map<String, dynamic> item) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Wrap(
        spacing: 28,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['product_name']?.toString() ?? '',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'SKU: ${item['sku'] ?? '-'} • Barcode: ${item['barcode'] ?? '-'}',
                ),
                if ((item['part_number']?.toString() ?? '').isNotEmpty)
                  Text('Part: ${item['part_number']}'),
              ],
            ),
          ),
          _value('Selling price', _money(item['selling_price'])),
          _value('Cost', _money(item['cost_price'])),
          _value('On hand', '${item['stock_quantity'] ?? 0}'),
          _value('Available', '${item['available_quantity'] ?? 0}'),
        ],
      ),
    ),
  );

  Widget _value(String label, String value) => SizedBox(
    width: 120,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}
