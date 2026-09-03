import 'dart:async';

import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/return_search_service.dart';
import 'purchase_detail_screen.dart';
import 'sale_detail_screen.dart';

class ReturnCenterScreen extends StatefulWidget {
  final ClientSession session;
  const ReturnCenterScreen({super.key, required this.session});

  @override
  State<ReturnCenterScreen> createState() => _ReturnCenterScreenState();
}

class _ReturnCenterScreenState extends State<ReturnCenterScreen>
    with SingleTickerProviderStateMixin {
  final ReturnSearchService _service = ReturnSearchService();
  final TextEditingController _search = TextEditingController();
  late final TabController _tabs;
  Timer? _debounce;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sales = const [];
  List<Map<String, dynamic>> _purchases = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  bool get _salesAllowed =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('sales.return') ||
      widget.session.hasPermission('sales.manage');

  bool get _purchaseAllowed =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('purchases.return') ||
      widget.session.hasPermission('purchases.manage');

  String get _deviceId => widget.session.device?.deviceId ?? '';

  Future<void> _load() async {
    if (_deviceId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This POS terminal is not assigned to a store.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _salesAllowed
            ? _service.searchToday(
                tenantId: widget.session.business.id,
                deviceId: _deviceId,
                type: 'sale',
                query: _search.text,
              )
            : Future.value(<Map<String, dynamic>>[]),
        _purchaseAllowed
            ? _service.searchToday(
                tenantId: widget.session.business.id,
                deviceId: _deviceId,
                type: 'purchase',
                query: _search.text,
              )
            : Future.value(<Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _sales = values[0];
        _purchases = values[1];
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _load);
  }

  String _money(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return widget.session.currencyCode == 'INR'
        ? '₹${amount.toStringAsFixed(2)}'
        : '${widget.session.currencyCode} ${amount.toStringAsFixed(2)}';
  }

  Future<void> _open(Map<String, dynamic> row) async {
    final type = row['entity_type']?.toString() ?? '';
    final id = row['entity_id']?.toString() ?? '';
    if (id.isEmpty) return;
    if (type == 'sale') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SaleDetailScreen(session: widget.session, saleId: id),
        ),
      );
    } else if (type == 'purchase') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PurchaseDetailScreen(session: widget.session, purchaseId: id),
        ),
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Returns',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        "Today's invoices on this POS",
                        style: TextStyle(
                          fontSize: 9.8,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Sales ${_sales.length} | Purchases ${_purchases.length}',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 620;

                final search = TextField(
                  controller: _search,
                  onChanged: _searchChanged,
                  onSubmitted: (_) => _load(),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 16),
                    hintText: 'Invoice, party, product, SKU or barcode...',
                  ),
                );

                final tabs = TabBar(
                  controller: _tabs,
                  labelStyle: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                  tabs: const [
                    Tab(text: 'Sales Return'),
                    Tab(text: 'Purchase Return'),
                  ],
                );

                if (narrow) {
                  return Column(
                    children: [search, const SizedBox(height: 4), tabs],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 5),
                    SizedBox(width: 250, child: tabs),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _resultList(
                        rows: _sales,
                        allowed: _salesAllowed,
                        deniedText:
                            'Sales Return permission is not assigned to this user.',
                        icon: Icons.assignment_return_outlined,
                      ),
                      _resultList(
                        rows: _purchases,
                        allowed: _purchaseAllowed,
                        deniedText:
                            'Purchase Return permission is not assigned to this user.',
                        icon: Icons.keyboard_return_outlined,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _resultList({
    required List<Map<String, dynamic>> rows,
    required bool allowed,
    required String deniedText,
    required IconData icon,
  }) {
    if (!allowed) return Center(child: Text(deniedText));
    if (rows.isEmpty) {
      return const Center(
        child: Text('No matching invoices from today on this POS.'),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            color: scheme.surfaceContainerHighest.withValues(alpha: .45),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Document',
                    style: TextStyle(
                      fontSize: 10.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    'Party / Product',
                    style: TextStyle(
                      fontSize: 10.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Status',
                    style: TextStyle(
                      fontSize: 10.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Amount',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                SizedBox(width: 54),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final returnStatus = (row['return_status'] ?? 'not_returned')
                    .toString()
                    .replaceAll('_', ' ')
                    .toUpperCase();
                final product = row['matched_product']?.toString().trim() ?? '';

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _open(row),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 46),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: scheme.outlineVariant),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                Icon(icon, size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${row['document_number'] ?? ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10.2,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${row['party'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 8.5),
                                ),
                                if (product.isNotEmpty)
                                  Text(
                                    product,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 8.8,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  returnStatus,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 9.8,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              _money(row['grand_total']),
                              maxLines: 1,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 10.2,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 54,
                            child: IconButton(
                              tooltip: 'Open',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _open(row),
                              icon: const Icon(Icons.open_in_new, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
