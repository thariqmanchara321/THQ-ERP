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
    return Padding(
      padding: const EdgeInsets.all(10),
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
                      'Returns',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      "Today's invoices on this POS only. Historical invoices are available in Terminal Daily.",
                      style: TextStyle(fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Reload',
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 7),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;
              final search = TextField(
                controller: _search,
                autofocus: false,
                onChanged: _searchChanged,
                onSubmitted: (_) => _load(),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText:
                      'Invoice / customer / supplier / product / barcode…',
                ),
              );
              final tabs = TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'Sales Return'),
                  Tab(text: 'Purchase Return'),
                ],
              );
              if (narrow) {
                return Column(
                  children: [search, const SizedBox(height: 6), tabs],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 8),
                  SizedBox(width: 270, child: tabs),
                ],
              );
            },
          ),
          const SizedBox(height: 7),
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
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final row = rows[index];
        final returnStatus = (row['return_status'] ?? 'not_returned')
            .toString()
            .replaceAll('_', ' ')
            .toUpperCase();
        final product = row['matched_product']?.toString().trim() ?? '';
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(icon, size: 19),
            title: Text(
              '${row['document_number'] ?? ''} • ${row['party'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              [
                '${row['document_date'] ?? ''}',
                returnStatus,
                if (product.isNotEmpty) product,
              ].join(' • '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9.5),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _money(row['grand_total']),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () => _open(row),
                  child: const Text('Open'),
                ),
              ],
            ),
            onTap: () => _open(row),
          ),
        );
      },
    );
  }
}
