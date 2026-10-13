import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/aggregate_yard_service.dart';
import '../services/location_scope_service.dart';

class DailyMaterialRateBoardScreen extends StatefulWidget {
  final ClientSession session;

  const DailyMaterialRateBoardScreen({super.key, required this.session});

  @override
  State<DailyMaterialRateBoardScreen> createState() =>
      _DailyMaterialRateBoardScreenState();
}

class _DailyMaterialRateBoardScreenState
    extends State<DailyMaterialRateBoardScreen> {
  final AggregateYardService _service = AggregateYardService();
  final TextEditingController _searchCtrl = TextEditingController();

  DateTime _effectiveDate = DateTime.now();
  List<Map<String, dynamic>> _rates = [];
  final Map<String, TextEditingController> _purchaseControllers = {};
  final Map<String, TextEditingController> _sellingControllers = {};
  final Map<String, TextEditingController> _wholesaleControllers = {};
  final Map<String, TextEditingController> _minSellingControllers = {};
  final Map<String, TextEditingController> _notesControllers = {};

  bool _loading = true;
  bool _saving = false;
  String? _error;

  String? get _locationId =>
      LocationScopeService.currentForRead(widget.session);
  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('aggregate_yard.manage') ||
      widget.session.hasPermission('inventory.manage');

  @override
  void initState() {
    super.initState();
    _loadRates();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final c in _purchaseControllers.values) {
      c.dispose();
    }
    for (final c in _sellingControllers.values) {
      c.dispose();
    }
    for (final c in _wholesaleControllers.values) {
      c.dispose();
    }
    for (final c in _minSellingControllers.values) {
      c.dispose();
    }
    for (final c in _notesControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRates() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _service.dailyRates(
        tenantId: widget.session.business.id,
        locationId: _locationId,
        date: _effectiveDate,
      );

      _purchaseControllers.clear();
      _sellingControllers.clear();
      _wholesaleControllers.clear();
      _minSellingControllers.clear();
      _notesControllers.clear();

      for (final r in rows) {
        final variantId = r['variant_id']?.toString() ?? '';
        _purchaseControllers[variantId] = TextEditingController(
          text: (r['purchase_rate'] ?? 0).toString(),
        );
        _sellingControllers[variantId] = TextEditingController(
          text: (r['selling_rate'] ?? 0).toString(),
        );
        _wholesaleControllers[variantId] = TextEditingController(
          text: (r['wholesale_rate'] ?? 0).toString(),
        );
        _minSellingControllers[variantId] = TextEditingController(
          text: (r['min_selling_rate'] ?? 0).toString(),
        );
        _notesControllers[variantId] = TextEditingController(
          text: r['notes'] ?? '',
        );
      }

      if (mounted) {
        setState(() {
          _rates = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _copyPreviousRates() {
    var count = 0;
    for (final r in _rates) {
      final variantId = r['variant_id']?.toString() ?? '';
      final prevPurchase = r['prev_purchase_rate'];
      final prevSelling = r['prev_selling_rate'];

      if (prevPurchase != null) {
        _purchaseControllers[variantId]?.text = prevPurchase.toString();
        count++;
      }
      if (prevSelling != null) {
        _sellingControllers[variantId]?.text = prevSelling.toString();
      }
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied previous rates for $count materials.')),
    );
  }

  Future<void> _saveRates() async {
    if (!_canManage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission aggregate_yard.manage required.')),
      );
      return;
    }

    setState(() => _saving = true);
    final payload = <Map<String, dynamic>>[];

    for (final r in _rates) {
      final variantId = r['variant_id']?.toString() ?? '';
      final pCtrl = _purchaseControllers[variantId];
      final sCtrl = _sellingControllers[variantId];
      final wCtrl = _wholesaleControllers[variantId];
      final mCtrl = _minSellingControllers[variantId];
      final nCtrl = _notesControllers[variantId];

      final purchaseRate = double.tryParse(pCtrl?.text.trim() ?? '') ?? 0.0;
      final sellingRate = double.tryParse(sCtrl?.text.trim() ?? '') ?? 0.0;
      final wholesaleRate = double.tryParse(wCtrl?.text.trim() ?? '') ?? 0.0;
      final minSellingRate = double.tryParse(mCtrl?.text.trim() ?? '') ?? 0.0;

      payload.add({
        'variant_id': variantId,
        'purchase_rate': purchaseRate,
        'selling_rate': sellingRate,
        'wholesale_rate': wholesaleRate,
        'min_selling_rate': minSellingRate,
        'notes': nCtrl?.text.trim() ?? '',
      });
    }

    try {
      final res = await _service.saveDailyRates(
        tenantId: widget.session.business.id,
        locationId: _locationId,
        effectiveDate: _effectiveDate,
        rates: payload,
      );

      if (mounted) {
        setState(() => _saving = false);
        if (res['success'] == true || res.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Daily material rates updated successfully. Historical records preserved.'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadRates();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null && picked != _effectiveDate) {
      setState(() => _effectiveDate = picked);
      await _loadRates();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateFormatted =
        '${_effectiveDate.year}-${_effectiveDate.month.toString().padLeft(2, '0')}-${_effectiveDate.day.toString().padLeft(2, '0')}';

    final query = _searchCtrl.text.trim().toLowerCase();
    final filteredRates = query.isEmpty
        ? _rates
        : _rates.where((r) {
            final name = (r['product_name'] ?? '').toString().toLowerCase();
            final variant = (r['variant_name'] ?? '').toString().toLowerCase();
            return name.contains(query) || variant.contains(query);
          }).toList();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 46,
        title: const Text('Daily Material Rate Board', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        actions: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.calendar_month, size: 15),
            label: Text(dateFormatted, style: const TextStyle(fontSize: 12)),
            onPressed: _selectDate,
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.history, size: 15),
            label: const Text('Copy Previous', style: TextStyle(fontSize: 12)),
            onPressed: _loading || _rates.isEmpty ? null : _copyPreviousRates,
          ),
          const SizedBox(width: 6),
          if (_canManage)
            FilledButton.icon(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.save_outlined, size: 15),
              label: Text(_saving ? 'Saving…' : 'Save Rates', style: const TextStyle(fontSize: 12)),
              onPressed: _loading || _saving ? null : _saveRates,
            ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // COMPACT INFO STRIP
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Daily rates serve as authoritative pricing suggestions for new draft purchases, sales, and load tickets on $dateFormatted. '
                    'Rate changes never rewrite posted historical invoices, journals or inventory batches.',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // SEARCH FILTER BAR
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  hintText: 'Filter materials or quality grades…',
                  hintStyle: const TextStyle(fontSize: 11.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),

          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: scheme.error, fontSize: 11)),
            ),

          // RATE TABLE
          Expanded(
            child: filteredRates.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 40,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _loading
                                ? 'Loading rate board…'
                                : _rates.isEmpty
                                    ? 'No bulk materials or grades found in inventory.\nAdd physical stock products to configure their daily rate board.'
                                    : 'No material grades match "${_searchCtrl.text}".',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (!_loading && _rates.isNotEmpty && _searchCtrl.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear, size: 14),
                              label: const Text('Clear search', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      child: Table(
                        columnWidths: const {
                          0: FlexColumnWidth(2.2), // Material / Grade
                          1: FlexColumnWidth(1.1), // Buy Rate
                          2: FlexColumnWidth(1.1), // Sell Rate
                          3: FlexColumnWidth(1.0), // Spread
                          4: FlexColumnWidth(1.0), // Wholesale
                          5: FlexColumnWidth(1.0), // Min Floor
                          6: FlexColumnWidth(1.0), // Margin %
                          7: FlexColumnWidth(1.6), // Notes
                        },
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        children: [
                          TableRow(
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
                            ),
                            children: const [
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                child: Text('Material / Grade', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                child: Text('Buy Rate (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                child: Text('Sell Rate (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                child: Text('Spread (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                child: Text('Wholesale (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                child: Text('Floor (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                child: Text('Margin', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                child: Text('Notes / Terms', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          ...filteredRates.map((r) {
                            final variantId = r['variant_id']?.toString() ?? '';
                            final pCtrl = _purchaseControllers[variantId];
                            final sCtrl = _sellingControllers[variantId];
                            final wCtrl = _wholesaleControllers[variantId];
                            final mCtrl = _minSellingControllers[variantId];
                            final nCtrl = _notesControllers[variantId];

                            final purchase = double.tryParse(pCtrl?.text ?? '') ?? 0;
                            final selling = double.tryParse(sCtrl?.text ?? '') ?? 0;
                            final minSelling = double.tryParse(mCtrl?.text ?? '') ?? purchase;
                            final spread = selling - purchase;

                            final marginPct = purchase > 0
                                ? ((selling - purchase) / purchase) * 100
                                : 0.0;
                            final hasMarginWarning = (selling < minSelling) || (selling < purchase);

                            final name = r['product_name'] ?? '';
                            final variantName = r['variant_name'] ?? '';
                            final unit = r['base_unit_code'] ?? 'CFT';

                            return TableRow(
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                              ),
                              children: [
                                // Material
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        variantName.isNotEmpty ? '$name • $variantName' : name,
                                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text('Unit: $unit', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                          const SizedBox(width: 6),
                                          if (r['has_today_rate'] != true)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: Text(
                                                'Rate not set',
                                                style: TextStyle(
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.amber.shade900,
                                                ),
                                              ),
                                            )
                                          else
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF00875A).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: const Text(
                                                'Active today',
                                                style: TextStyle(
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF00875A),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Buy Rate
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                  child: SizedBox(
                                    height: 32,
                                    child: TextField(
                                      controller: pCtrl,
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(fontSize: 12),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ),
                                // Sell Rate
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                  child: SizedBox(
                                    height: 32,
                                    child: TextField(
                                      controller: sCtrl,
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(fontSize: 12),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                        suffixIcon: hasMarginWarning
                                            ? const Tooltip(
                                                message: 'Selling price is below purchase or minimum floor!',
                                                child: Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 16),
                                              )
                                            : null,
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ),
                                // Spread
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                  child: Text(
                                    '₹${spread.toStringAsFixed(2)}',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: spread < 0 ? scheme.error : const Color(0xFF00875A),
                                    ),
                                  ),
                                ),
                                // Wholesale
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                  child: SizedBox(
                                    height: 32,
                                    child: TextField(
                                      controller: wCtrl,
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(fontSize: 12),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ),
                                // Floor
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                  child: SizedBox(
                                    height: 32,
                                    child: TextField(
                                      controller: mCtrl,
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(fontSize: 12),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ),
                                // Margin %
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: marginPct < 0
                                            ? scheme.error.withValues(alpha: 0.12)
                                            : marginPct < 10
                                                ? Colors.amber.withValues(alpha: 0.15)
                                                : const Color(0xFF00875A).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${marginPct.toStringAsFixed(1)}%',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: marginPct < 0
                                              ? scheme.error
                                              : marginPct < 10
                                                  ? Colors.amber.shade900
                                                  : const Color(0xFF00875A),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Notes
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                  child: SizedBox(
                                    height: 32,
                                    child: TextField(
                                      controller: nCtrl,
                                      style: const TextStyle(fontSize: 11),
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                        hintText: 'Terms/notes',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
